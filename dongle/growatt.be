#- DongleGrowatt - Growatt SPF inverter driver for the ShineWiFi-X2 stick
 #
 # - Polls the inverter over Modbus RTU (USB -> CH340 -> GPIO0 TX / GPIO1 RX, 115200 8N1)
 # - Publishes the values in the telemetry JSON (MQTT "SENSOR" message) and on the main web page
 # - Modbus TCP server (default port 502) that forwards requests to the inverter, read-only by default
 # - Serial, firmware, clock and settings on tele/<topic>/GROWATT_INFO, BMS data on tele/<topic>/GROWATT_BMS
 # - Commands GrowattSet <name> <value> and GrowattClock (off by default; safe list, limits, read back)
 # - "Dongle settings" web page: network (DHCP / static), MQTT (with test), device name,
 #   admin password, Modbus options
 #
 # Copyright (C) 2026 Barbu Dan-Cristian - GPL-3.0-or-later
 -#

import persist
import webserver
import json
import string
import mqtt

GW_STATUS = ["Standby", "-", "Discharge", "Fault", "Firmware update", "PV charge", "AC charge",
                 "Combined charge", "Combined charge + bypass", "PV charge + bypass",
                 "AC charge + bypass", "Bypass", "PV charge + discharge"]
GW_OUTPUT_PRIO = ["SBU", "SOL", "UTI", "SUB"]
GW_CHARGE_PRIO = ["Solar first", "Solar + utility", "Solar only"]
var GW_BATT_TYPE   = ["AGM", "Flooded", "User", "Lithium", "User2"]

# Inverter settings published on tele/<topic>/GROWATT_INFO and writable with the
# GrowattSet command. Names follow the ones Solar Assistant uses, so dashboards can
# work with either source. Ranges come from the SPF 6000 ES Plus manual.
#   [name, holding register, kind, options or min, max, scale]
#   kind "e" = list of options (value = index), "n" = number (raw = value / scale)
# Not writable on purpose: remote on/off (H0), output voltage and frequency (H18, H19)
# and battery type (H39): a wrong value there can switch the output off, damage
# appliances or stop the BMS link. They are still shown, read-only.
GW_SETTINGS = [
  ["output_source_priority", 1, "e", ["Solar/Battery/Utility", "Solar first", "Utility first", "Solar/Utility/Battery"]],
  ["charger_source_priority", 2, "e", ["Solar first", "Solar and utility simultaneously", "Solar only"]],
  ["energy_priority", 116, "e", ["Battery/Load/Utility", "Load/Battery/Utility"]],
  ["ac_input_range", 8, "e", ["Appliance", "UPS", "Generator"]],
  ["max_charge_current", 34, "n", 10, 150, 1],
  ["max_grid_charge_current", 38, "n", 0, 80, 1],
  ["max_generator_charge_current", 83, "n", 0, 80, 1],
  ["battery_absorption_charge_voltage", 35, "n", 48, 58.4, 0.1],
  ["battery_float_charge_voltage", 36, "n", 48, 58.4, 0.1],
  ["to_grid_battery_capacity", 37, "n", 0, 100, 0.1],
  ["back_to_battery_capacity", 95, "n", 0, 100, 0.1],
  ["shutdown_battery_capacity", 82, "n", 0, 100, 0.1],
  ["grid_output_start_hour", 3, "n", 0, 23, 1],
  ["grid_output_stop_hour", 4, "n", 0, 23, 1],
  ["grid_charge_start_hour", 5, "n", 0, 23, 1],
  ["grid_charge_stop_hour", 6, "n", 0, 23, 1],
  ["buzzer", 22, "e", ["Off", "On"]],
  ["overload_restart", 20, "n", 0, 2, 1],
  ["overtemperature_restart", 21, "n", 0, 1, 1],
]
GW_READONLY = [
  ["remote_switch", 0, "e", ["Off", "On"]],
  ["battery_type", 39, "e", ["AGM", "Flooded", "User", "Lithium BMS", "User 2"]],
  ["output_voltage", 18, "e", ["208 V", "230 V", "240 V", "220 V", "100 V", "110 V", "120 V"]],
  ["output_frequency", 19, "e", ["50 Hz", "60 Hz"]],
]

class GrowattDongle
  # ---- configuration (persisted) ----
  var addr, poll_s, tcp_port, tcp_write, tx_pin, rx_pin, baud, set_write
  # ---- serial / Modbus RTU engine ----
  var ser, queue, tcpq, job, rxbuf, deadline, next_send
  # ---- data ----
  var inp, hold, last_ok, polls_ok, polls_err, next_poll, next_hold
  # ---- Modbus TCP ----
  var srv, clients, tcp_req, tcp_err
  # ---- settings writes / extra MQTT topics ----
  var wbusy, last_set, bms_ok, info_due   # info_due: MQTT was connected at the last check

  def init()
    self.addr      = int(persist.find("gw_addr", 1))
    self.poll_s    = int(persist.find("gw_poll", 10))
    self.tcp_port  = int(persist.find("gw_tcp_port", 502))
    self.tcp_write = persist.find("gw_tcp_write", false)
    self.set_write = persist.find("gw_set_write", false)
    self.tx_pin    = int(persist.find("gw_tx", 0))
    self.rx_pin    = int(persist.find("gw_rx", 1))
    self.baud      = int(persist.find("gw_baud", 115200))

    self.queue = []
    self.tcpq = []
    self.job = nil
    self.rxbuf = bytes()
    self.next_send = 0
    self.inp = {}
    self.hold = {}
    self.last_ok = 0
    self.polls_ok = 0
    self.polls_err = 0
    self.next_poll = tasmota.millis() + 3000
    self.next_hold = 0
    self.clients = []
    self.tcp_req = 0
    self.tcp_err = 0
    self.wbusy = false
    self.last_set = nil
    self.bms_ok = false
    self.info_due = false

    try
      self.ser = serial(self.rx_pin, self.tx_pin, self.baud, serial.SERIAL_8N1)
      tasmota.log(f"GRW: serial ready rx=GPIO{self.rx_pin} tx=GPIO{self.tx_pin} {self.baud} baud", 2)
    except .. as e, m
      self.ser = nil
      tasmota.log(f"GRW: cannot open serial: {e} {m}", 1)
    end

    tasmota.add_driver(self)
    tasmota.add_cmd("GrowattSet", def (cmd, idx, payload) self.cmd_set(payload) end)
    tasmota.add_cmd("GrowattClock", def (cmd, idx, payload) self.cmd_clock() end)
    tasmota.add_fast_loop(/-> self.loop())
    if tasmota.is_network_up() self.web_add_handler() end
  end

  # ======================================================================
  # Modbus RTU engine (one request on the wire at a time, FIFO queue)
  # ======================================================================
  def crc16(b)
    var crc = 0xFFFF
    var i = 0
    while i < size(b)
      crc = crc ^ b[i]
      var j = 0
      while j < 8
        if (crc & 1) != 0
          crc = (crc >> 1) ^ 0xA001
        else
          crc = crc >> 1
        end
        j += 1
      end
      i += 1
    end
    return crc
  end

  # pdu = bytes starting with the slave address, without CRC; cb(resp) gets the response
  # (address .. data, without CRC) or nil on timeout / CRC error
  # TCP requests (tcp = true) have their own queue, served before the polling queue
  def enqueue(pdu, cb, tcp)
    var q = tcp ? self.tcpq : self.queue
    if size(q) > 20
      cb(nil)
      return
    end
    q.push([pdu, cb])
  end

  def expected_len(b)
    if size(b) < 3 return 0 end
    var fc = b[1]
    if (fc & 0x80) != 0 return 5 end
    if fc == 3 || fc == 4 || fc == 1 || fc == 2 return 5 + b[2] end
    return 8      # 5, 6, 15, 16
  end

  def loop()
    if self.ser == nil return end
    var now = tasmota.millis()

    if self.job != nil
      var n = self.ser.available()
      if n > 0 self.rxbuf = self.rxbuf + self.ser.read() end
      var want = self.expected_len(self.rxbuf)
      if want > 0 && size(self.rxbuf) >= want
        var frame = self.rxbuf[0 .. want - 1]
        var body = frame[0 .. want - 3]
        var crc = frame.get(want - 2, 2)        # little endian
        var cb = self.job[1]
        var asked = self.job[0][0]
        self.job = nil
        self.next_send = now + 15
        if crc == self.crc16(body) && body[0] == asked
          cb(body)
        else
          cb(nil)
        end
      elif now > self.deadline
        var cb = self.job[1]
        self.job = nil
        self.next_send = now + 15
        cb(nil)
      end
    elif (size(self.tcpq) > 0 || size(self.queue) > 0) && now >= self.next_send
      var q = size(self.tcpq) > 0 ? self.tcpq : self.queue
      self.job = q[0]
      q.remove(0)
      if self.ser.available() > 0 self.ser.read() end     # drop stray bytes
      self.rxbuf = bytes()
      var pdu = self.job[0]
      var frame = pdu.copy()
      frame.add(self.crc16(pdu), 2)                       # CRC little endian
      self.ser.write(frame)
      self.deadline = now + 1000
    end

    self.tcp_loop()

    if now >= self.next_poll
      self.next_poll = now + self.poll_s * 1000
      self.poll()
    end
  end

  # ======================================================================
  # Polling
  # ======================================================================
  def read_req(fc, start, count)
    var p = bytes()
    p.add(self.addr, 1)
    p.add(fc, 1)
    p.add(start, -2)
    p.add(count, -2)
    return p
  end

  def store(regs, start, resp)
    if resp == nil || (resp[1] & 0x80) != 0 return false end
    var n = resp[2] / 2
    var i = 0
    while i < n
      regs[start + i] = resp.get(3 + 2 * i, -2)
      i += 1
    end
    return true
  end

  def poll()
    self.enqueue(self.read_req(4, 0, 45), def (r)
      if self.store(self.inp, 0, r) self.last_ok = tasmota.millis() self.polls_ok += 1 else self.polls_err += 1 end
    end)
    self.enqueue(self.read_req(4, 45, 45), def (r)
      if !self.store(self.inp, 45, r) self.polls_err += 1 end
    end)
    # BMS block: only the inverter wired to the BMS has values here
    self.enqueue(self.read_req(4, 200, 50), def (r)
      self.bms_ok = self.store(self.inp, 200, r) && (self.inp.find(203, 0) > 0 || self.inp.find(204, 0) > 0)
      if self.bms_ok self.publish("GROWATT_BMS", self.bms()) end
    end)
    var now = tasmota.millis()
    if now >= self.next_hold
      self.next_hold = now + 60000
      self.read_settings()
    end
  end

  # holding 0-128 (settings, clock, serial, firmware) and the generator inputs
  def read_settings()
    self.enqueue(self.read_req(3, 0, 45), def (r) self.store(self.hold, 0, r) end)
    self.enqueue(self.read_req(3, 45, 45), def (r) self.store(self.hold, 45, r) end)
    self.enqueue(self.read_req(3, 90, 39), def (r) self.store(self.hold, 90, r) end)
    self.enqueue(self.read_req(4, 96, 2), def (r)
      self.store(self.inp, 96, r)
      self.publish("GROWATT_INFO", self.info())
    end)
  end

  # publishes on tele/<topic>/<name>
  def publish(name, v)
    if v == nil || !mqtt.connected() return end
    var t = self.topic()
    if size(t) == 0 return end
    mqtt.publish(f"tele/{t}/{name}", json.dump(v))
  end

  # MQTT topic as used on the wire: the default "growatt_%06X" becomes "growatt_3000E0"
  # (last 6 hex digits of the MAC), the same way the firmware expands it
  def topic()
    var t = self.cmd_val("Topic")
    var p = string.find(t, "%06X")
    if p >= 0
      var mac = string.split(tasmota.wifi().find("mac", ""), ":")
      var hex = size(mac) == 6 ? mac[3] + mac[4] + mac[5] : ""
      t = t[0 .. p - 1] + string.toupper(hex) + t[p + 4 ..]
    end
    return t
  end

  # ---- register helpers ----
  def u16(r)  return self.inp.find(r) end
  def u32(r)
    var hi = self.inp.find(r)
    var lo = self.inp.find(r + 1)
    if hi == nil || lo == nil return nil end
    return (hi << 16) | lo                   # Berry ints are 32 bit: signed values wrap correctly
  end
  def sc(v, f)
    if v == nil return nil end
    return v * f
  end
  def online()
    return self.last_ok > 0 && (tasmota.millis() - self.last_ok) < (self.poll_s * 3000 + 5000)
  end
  def pick(lst, v)
    if v == nil return nil end
    if v >= 0 && v < size(lst) return lst[v] end
    return f"Unknown ({v})"
  end

  def s16(v)
    if v == nil return nil end
    return v >= 0x8000 ? v - 0x10000 : v
  end
  def ascii(start, n)
    var b = bytes()
    var i = 0
    while i < n
      var w = self.hold.find(start + i)
      if w == nil return nil end
      for c: [w >> 8, w & 0xFF]
        if c >= 0x20 && c < 0x7F b.add(c, 1) end
      end
      i += 1
    end
    return b.asstring()
  end

  def values()
    if !self.online() return nil end
    var pv1 = self.sc(self.u32(3), 0.1)
    var pv2 = self.sc(self.u32(5), 0.1)
    var chg = self.sc(self.u16(83), 0.1)
    var dis = self.sc(self.u16(84), 0.1)
    return {
      "Status": self.pick(GW_STATUS, self.u16(0)),
      "StatusCode": self.u16(0),
      "PV1": {"Voltage": self.sc(self.u16(1), 0.1), "Current": self.sc(self.u16(7), 0.1), "Power": pv1},
      "PV2": {"Voltage": self.sc(self.u16(2), 0.1), "Current": self.sc(self.u16(8), 0.1), "Power": pv2},
      "PVPower": (pv1 != nil && pv2 != nil) ? pv1 + pv2 : nil,
      "Battery": {"SOC": self.u16(18), "Voltage": self.sc(self.u16(17), 0.01),
                  "Power": self.sc(self.u32(77), 0.1), "DischargePower": self.sc(self.u32(73), 0.1),
                  "ChargeCurrent": chg, "DischargeCurrent": dis,
                  "Current": (chg != nil && dis != nil) ? chg - dis : nil},
      "Output": {"Voltage": self.sc(self.u16(22), 0.1), "Frequency": self.sc(self.u16(23), 0.01),
                 "Current": self.sc(self.u16(34), 0.1), "Power": self.sc(self.u32(9), 0.1),
                 "ApparentPower": self.sc(self.u32(11), 0.1), "Load": self.sc(self.u16(27), 0.1)},
      "Grid": {"Voltage": self.sc(self.u16(20), 0.1), "Frequency": self.sc(self.u16(21), 0.01),
               "Power": self.sc(self.u32(36), 0.1), "ApparentPower": self.sc(self.u32(38), 0.1),
               "ACChargePower": self.sc(self.u32(13), 0.1), "ACChargeCurrent": self.sc(self.u16(68), 0.1),
               "BypassPower": self.sc(self.u32(69), 0.1)},
      "Inverter": {"Temperature": self.sc(self.u16(25), 0.1), "DCDCTemperature": self.sc(self.u16(26), 0.1),
                   "MPPT1Temperature": self.sc(self.u16(32), 0.1), "MPPT2Temperature": self.sc(self.u16(33), 0.1),
                   "Current": self.sc(self.u16(35), 0.1), "BusVoltage": self.sc(self.u16(19), 0.1),
                   "FanMPPT": self.u16(81), "FanInverter": self.u16(82),
                   "FaultBits": self.u16(40), "WarningBits": self.u16(41),
                   "FaultCode": self.u16(42), "WarningCode": self.u16(43)},
      "Energy": {"PVToday": self.sc(self.u32(48), 0.1), "PVTotal": self.sc(self.u32(50), 0.1),
                 "LoadToday": self.sc(self.u32(85), 0.1), "LoadTotal": self.sc(self.u32(87), 0.1),
                 "ACChargeToday": self.sc(self.u32(56), 0.1), "ACChargeTotal": self.sc(self.u32(58), 0.1),
                 "DischargeToday": self.sc(self.u32(60), 0.1), "DischargeTotal": self.sc(self.u32(62), 0.1),
                 "ACDischargeToday": self.sc(self.u32(64), 0.1), "ACDischargeTotal": self.sc(self.u32(66), 0.1)},
      "Settings": {"OutputPriority": self.pick(GW_OUTPUT_PRIO, self.hold.find(1)),
                   "ChargerPriority": self.pick(GW_CHARGE_PRIO, self.hold.find(2)),
                   "BatteryType": self.pick(GW_BATT_TYPE, self.hold.find(39)),
                   "MaxChargeCurrent": self.hold.find(34)}
    }
  end

  # BMS data, only on the inverter that talks to the battery (tele/<topic>/GROWATT_BMS)
  def bms()
    if !self.bms_ok return nil end
    var cmax = self.u16(243)
    var cmin = self.u16(244)
    return {
      "Status": self.u16(200), "Error": self.u16(201), "Warning": self.u16(202),
      "SOC": self.u16(203), "SOH": self.u16(237), "Voltage": self.sc(self.u16(204), 0.01),
      "Current": self.sc(self.s16(self.u16(205)), 0.1), "Temperature": self.sc(self.s16(self.u16(206)), 0.1),
      "MaxChargeCurrent": self.sc(self.u16(207), 0.01), "ChargeVoltage": self.sc(self.u16(208), 0.01),
      "Cycles": self.u16(242),     # 241 and 242 are separate counters; 242 matches Solar Assistant and the BMS
      "CellMax": self.sc(cmax, 0.001), "CellMin": self.sc(cmin, 0.001),
      "CellDelta": (cmax != nil && cmin != nil) ? cmax - cmin : nil
    }
  end

  # value of one setting in real units / option text, nil if unknown
  def setting_value(st)
    var raw = self.hold.find(st[1])
    if raw == nil return nil end
    if st[2] == "e"
      return (raw >= 0 && raw < size(st[3])) ? st[3][raw] : str(raw)
    end
    if (st[1] == 37 || st[1] == 82 || st[1] == 95) && self.hold.find(39) != 3 return nil end   # in volts on lead batteries
    var v = raw * st[5]
    return st[5] < 1 ? real(format("%.1f", v)) : int(v)
  end

  # serial, firmware, clock and all settings (tele/<topic>/GROWATT_INFO, every minute)
  def info()
    if self.hold.find(9) == nil return nil end
    var set = {}
    for st: GW_SETTINGS set[st[0]] = self.setting_value(st) end
    for st: GW_READONLY set[st[0]] = self.setting_value(st) end
    var clock = nil
    if self.hold.find(50) != nil
      clock = format("%04d-%02d-%02d %02d:%02d:%02d", self.hold[45], self.hold[46], self.hold[47],
                     self.hold[48], self.hold[49], self.hold[50])
    end
    return {
      "Serial": self.ascii(23, 5), "Firmware": self.ascii(9, 3), "ControlFirmware": self.ascii(12, 3),
      "DeviceType": self.hold.find(43), "RatedPower": self.hold.find(79) != nil ? ((self.hold[78] << 16) | self.hold[79]) / 10 : nil,
      "Clock": clock, "Generator": {"Power": self.u16(96), "Voltage": self.sc(self.u16(97), 0.1)},
      "Writable": self.set_write, "LastSet": self.last_set,
      "Settings": set
    }
  end

  # ======================================================================
  # Settings changes: GrowattSet <name> <value>, GrowattClock
  # ======================================================================
  def set_result(name, val, ok, msg)
    self.last_set = {"Name": name, "Value": val, "Result": ok ? "OK" : "Error", "Message": msg}
    tasmota.log(f"GRW: set {name} = {val}: {msg}", 2)
    self.publish("GROWATT_SET", self.last_set)
  end

  def cmd_set(payload)
    var p = string.find(payload, " ")
    var name = p > 0 ? payload[0 .. p - 1] : payload
    var val = p > 0 ? payload[p + 1 ..] : ""
    var err = self.write_setting(name, val)
    if err == nil
      tasmota.resp_cmnd(json.dump({"GrowattSet": {"Name": name, "Value": val, "Result": "Queued"}}))
    else
      tasmota.resp_cmnd(json.dump({"GrowattSet": {"Name": name, "Value": val, "Result": "Error", "Message": err}}))
      self.set_result(name, val, false, err)        # also visible in Home Assistant (last setting change)
      self.publish("GROWATT_INFO", self.info())
    end
  end

  # checks the value and queues the write; returns nil or the reason it was refused
  def write_setting(name, val)
    if !self.set_write return "settings changes are off (Dongle settings page)" end
    if self.wbusy return "another change is in progress" end
    if !self.online() return "inverter not answering" end
    var st = nil
    for s: GW_SETTINGS if s[0] == name st = s end end
    if st == nil return "unknown or read-only setting" end
    var raw = nil
    if st[2] == "e"
      for i: 0 .. size(st[3]) - 1
        if string.tolower(st[3][i]) == string.tolower(val) || str(i) == val raw = i end
      end
      if raw == nil return "value must be one of: " + st[3].concat(", ") end
    else
      var n = real(val)
      if size(val) == 0 || (n == 0 && val[0] != "0") return "value must be a number" end
      if n < st[3] || n > st[4] return f"value must be between {st[3]} and {st[4]}" end
      if (st[1] == 37 || st[1] == 82 || st[1] == 95) && self.hold.find(39) != 3 return "only for lithium batteries" end
      raw = int(n / st[5] + 0.5)
    end
    self.write_reg(name, st[1], raw, val)
    return nil
  end

  # FC06, then reads the register back and reports the result
  def write_reg(name, reg, raw, val)
    self.wbusy = true
    var p = bytes()
    p.add(self.addr, 1)
    p.add(6, 1)
    p.add(reg, -2)
    p.add(raw, -2)
    self.enqueue(p, def (r)
      if r == nil || (r[1] & 0x80) != 0
        self.wbusy = false
        self.set_result(name, val, false, r == nil ? "no answer from the inverter" : f"refused by the inverter (code {r[2]})")
        return
      end
      self.enqueue(self.read_req(3, reg, 1), def (rb)
        self.wbusy = false
        if self.store(self.hold, reg, rb) && self.hold[reg] == raw
          self.set_result(name, val, true, "saved and read back")
          self.publish("GROWATT_INFO", self.info())
        else
          self.set_result(name, val, false, "inverter did not keep the value")
        end
      end, true)
    end, true)
  end

  # writes the dongle's local time (from NTP) into the inverter clock H45-H50
  def cmd_clock()
    var err = nil
    var t = tasmota.rtc()["local"]
    if !self.set_write err = "settings changes are off (Dongle settings page)"
    elif self.wbusy err = "another change is in progress"
    elif !self.online() err = "inverter not answering"
    elif t < 1700000000 err = "dongle time not set yet (no NTP)"
    end
    if err != nil
      tasmota.resp_cmnd(json.dump({"GrowattClock": {"Result": "Error", "Message": err}}))
      self.set_result("clock", "", false, err)
      self.publish("GROWATT_INFO", self.info())
      return
    end
    var d = tasmota.time_dump(t)
    var vals = [d["year"], d["month"], d["day"], d["hour"], d["min"], d["sec"]]
    var txt = format("%04d-%02d-%02d %02d:%02d:%02d", vals[0], vals[1], vals[2], vals[3], vals[4], vals[5])
    self.wbusy = true
    var fails = []
    var i = 0
    while i < 6
      var reg = 45 + i
      var p = bytes()
      p.add(self.addr, 1) p.add(6, 1) p.add(reg, -2) p.add(vals[i], -2)
      var last = (i == 5)
      self.enqueue(p, def (r)
        if r == nil || (r[1] & 0x80) != 0 fails.push(reg) end
        if last
          self.wbusy = false
          self.set_result("clock", txt, size(fails) == 0, size(fails) == 0 ? "clock set" : f"registers not written: {fails}")
          self.read_settings()
        end
      end, true)
      i += 1
    end
    tasmota.resp_cmnd(json.dump({"GrowattClock": {"Value": txt, "Result": "Queued"}}))
  end

  # telemetry (MQTT tele/<topic>/SENSOR), sent every TelePeriod
  def json_append()
    var v = self.values()
    if v == nil
      tasmota.response_append(',"Growatt":{"Online":false}')
      return
    end
    v["Online"] = true
    tasmota.response_append(',"Growatt":' + json.dump(v))
  end

  # main web page
  def fmt(v, d, unit)
    if v == nil return "-" end
    return format("%." + str(d) + "f", v) + " " + unit
  end
  def web_sensor()
    if self.ser == nil
      tasmota.web_send("{s}Inverter{m}<b>serial port error</b>{e}")
      return
    end
    var v = self.values()
    if v == nil
      tasmota.web_send("{s}Inverter{m}<b>no answer</b>{e}")
      return
    end
    var b = v["Battery"]
    var o = v["Output"]
    var e = v["Energy"]
    var bp = b["Power"]
    var bstate = bp == nil ? "-" : (bp > 15 ? "discharging" : (bp < -15 ? "charging" : "idle"))
    var msg = "{s}<b>Inverter</b>{m}" + str(v["Status"]) + "{e}"
    msg += "{s}Battery{m}" + str(b["SOC"]) + " % &middot; " + self.fmt(b["Voltage"], 2, "V") + "{e}"
    msg += "{s}Battery power{m}" + self.fmt(bp == nil ? nil : (bp < 0 ? -bp : bp), 0, "W") + " " + bstate + "{e}"
    msg += "{s}PV power{m}" + self.fmt(v["PVPower"], 0, "W") + "{e}"
    msg += "{s}PV1{m}" + self.fmt(v["PV1"]["Voltage"], 1, "V") + " &middot; " + self.fmt(v["PV1"]["Power"], 0, "W") + "{e}"
    msg += "{s}PV2{m}" + self.fmt(v["PV2"]["Voltage"], 1, "V") + " &middot; " + self.fmt(v["PV2"]["Power"], 0, "W") + "{e}"
    msg += "{s}Load{m}" + self.fmt(o["Power"], 0, "W") + " &middot; " + self.fmt(o["Load"], 1, "%") + "{e}"
    msg += "{s}AC output{m}" + self.fmt(o["Voltage"], 1, "V") + " &middot; " + self.fmt(o["Frequency"], 2, "Hz") + "{e}"
    msg += "{s}Inverter temperature{m}" + self.fmt(v["Inverter"]["Temperature"], 1, "&deg;C") + "{e}"
    msg += "{s}Produced today{m}" + self.fmt(e["PVToday"], 1, "kWh") + "{e}"
    msg += "{s}Consumed today{m}" + self.fmt(e["LoadToday"], 1, "kWh") + "{e}"
    var s = v["Settings"]
    if s["OutputPriority"] != nil
      msg += "{s}Settings{m}" + str(s["OutputPriority"]) + " &middot; " + str(s["ChargerPriority"]) + " &middot; " + str(s["BatteryType"]) + "{e}"
    end
    if self.bms_ok
      var m = self.bms()
      msg += "{s}BMS{m}" + str(m["SOC"]) + " % &middot; SOH " + str(m["SOH"]) + " % &middot; " + str(m["Cycles"]) + " cycles{e}"
    end
    var sn = self.ascii(23, 5)
    if sn != nil msg += "{s}Inverter serial{m}" + self.esc(sn) + " &middot; FW " + self.esc(self.ascii(9, 3)) + "{e}" end
    msg += "{s}Modbus TCP{m}" + (self.srv != nil ? f"port {self.tcp_port}, {size(self.clients)} client(s)" : "off") + "{e}"
    tasmota.web_send(msg)
  end

  # ======================================================================
  # Modbus TCP server -> RTU gateway
  # ======================================================================
  def start_tcp()
    if self.srv != nil || self.tcp_port <= 0 return end
    try
      self.srv = tcpserver(self.tcp_port)
      tasmota.log(f"GRW: Modbus TCP on port {self.tcp_port}", 2)
    except .. as e, m
      tasmota.log(f"GRW: cannot start Modbus TCP: {e} {m}", 1)
    end
  end

  def tcp_loop()
    if self.srv == nil return end
    if self.srv.hasclient()
      var c = self.srv.accept()
      if size(self.clients) >= 3
        c.close()
      else
        self.clients.push({"c": c, "buf": bytes()})
      end
    end
    var i = 0
    while i < size(self.clients)
      var cl = self.clients[i]
      var c = cl["c"]
      if !c.connected()
        c.close()
        self.clients.remove(i)
        continue
      end
      if c.available() > 0
        cl["buf"] = cl["buf"] + c.readbytes()
      end
      self.tcp_frames(cl)
      i += 1
    end
  end

  # MBAP: tid(2) proto(2) len(2) unit(1) | fc data...
  def tcp_frames(cl)
    var buf = cl["buf"]
    while size(buf) >= 8
      var len = buf.get(4, -2)
      if len < 2 || len > 254
        cl["buf"] = bytes()
        return
      end
      if size(buf) < 6 + len break end
      var tid = buf.get(0, -2)
      var unit = buf[6]
      var pdu = buf[7 .. 5 + len]                # fc + data
      buf = size(buf) > 6 + len ? buf[6 + len ..] : bytes()
      self.tcp_request(cl["c"], tid, unit, pdu)
    end
    cl["buf"] = buf
  end

  def tcp_reply(c, tid, unit, pdu)
    var r = bytes()
    r.add(tid, -2)
    r.add(0, -2)
    r.add(size(pdu) + 1, -2)
    r.add(unit, 1)
    r = r + pdu
    if c.connected() c.write(r) end
  end

  def tcp_request(c, tid, unit, pdu)
    self.tcp_req += 1
    var fc = pdu[0]
    var is_write = (fc == 5 || fc == 6 || fc == 15 || fc == 16)
    if (is_write && !self.tcp_write) || !(fc == 1 || fc == 2 || fc == 3 || fc == 4 || is_write)
      var ex = bytes()
      ex.add(fc | 0x80, 1)
      ex.add(1, 1)                                # illegal function
      self.tcp_reply(c, tid, unit, ex)
      return
    end
    var slave = (unit == 0 || unit == 255) ? self.addr : unit
    var rtu = bytes()
    rtu.add(slave, 1)
    rtu = rtu + pdu
    self.enqueue(rtu, def (resp)
      if resp == nil
        self.tcp_err += 1
        var ex = bytes()
        ex.add(fc | 0x80, 1)
        ex.add(0x0B, 1)                           # gateway target failed to respond
        self.tcp_reply(c, tid, unit, ex)
      else
        self.tcp_reply(c, tid, unit, resp[1 ..])
      end
    end, true)                                    # TCP queue: served before polling
  end

  def every_second()
    if self.srv == nil && tasmota.is_network_up() self.start_tcp() end
    # send the settings right after MQTT (re)connects, not only once a minute
    var up = mqtt.connected()
    if up && !self.info_due self.publish("GROWATT_INFO", self.info()) end
    self.info_due = up
  end

  # ======================================================================
  # Settings page
  # ======================================================================
  def web_add_main_button()
    webserver.content_send("<p></p><form action='gw' method='get'><button>Dongle settings</button></form>")
  end
  def web_add_config_button()
    webserver.content_send("<p></p><form action='gw' method='get'><button>Dongle settings</button></form>")
  end
  def web_add_handler()
    webserver.on("/gw", / -> self.page(), webserver.HTTP_GET)
    webserver.on("/gw", / -> self.page_post(), webserver.HTTP_POST)
  end

  def cmd_val(c)
    var r = tasmota.cmd(c, true)
    if r == nil return "" end
    for k: r.keys() return str(r[k]) end
    return ""
  end
  def ip_only(s)
    # "0.0.0.0 (192.168.1.5)" -> "0.0.0.0"
    var p = string.find(s, " ")
    return p > 0 ? s[0 .. p - 1] : s
  end
  def esc(s) return webserver.html_escape(str(s)) end

  def field(label, name, value, typ, extra)
    return f"<p><b>{label}</b><br><input id='{name}' name='{name}' type='{typ}' value='{self.esc(value)}' {extra}></p>"
  end

  def page(note)
    if !webserver.check_privileged_access() return nil end
    var ip   = self.ip_only(self.cmd_val("IPAddress1"))
    var gw   = self.ip_only(self.cmd_val("IPAddress2"))
    var mask = self.ip_only(self.cmd_val("IPAddress3"))
    var dns  = self.ip_only(self.cmd_val("IPAddress4"))
    var dhcp = (ip == "0.0.0.0" || ip == "")
    var w = tasmota.wifi()
    var cur_ip = w.find("ip", "-")

    webserver.content_start("Dongle settings")
    webserver.content_send_style()
    if note != nil
      webserver.content_send(f"<p style='padding:8px;border-radius:4px;background:#1f6f43;color:#fff'>{note}</p>")
    end
    webserver.content_send("<form method='post' action='gw'>")

    # ---- device ----
    webserver.content_send("<fieldset><legend><b>&nbsp;Device&nbsp;</b></legend>")
    webserver.content_send(self.field("Device name", "dn", self.cmd_val("DeviceName"), "text", "maxlength='32'"))
    webserver.content_send(self.field("New admin password (user: admin, empty = unchanged)", "wp", "", "password", "autocomplete='new-password'"))
    webserver.content_send("</fieldset><p></p>")

    # ---- network ----
    webserver.content_send(f"<fieldset><legend><b>&nbsp;Network&nbsp;</b></legend><p>Current address: <b>{cur_ip}</b></p>")
    var c_dhcp = dhcp ? " checked" : ""
    var c_static = dhcp ? "" : " checked"
    webserver.content_send(f"<p><label><input type='radio' name='ipm' value='dhcp'{c_dhcp}> DHCP (automatic)</label><br>")
    webserver.content_send(f"<label><input type='radio' name='ipm' value='static'{c_static}> Static address</label></p>")
    webserver.content_send(self.field("IP address", "ip1", dhcp ? "" : ip, "text", "placeholder='192.168.1.50'"))
    webserver.content_send(self.field("Gateway", "ip2", dhcp ? "" : gw, "text", "placeholder='192.168.1.1'"))
    webserver.content_send(self.field("Subnet mask", "ip3", dhcp ? "255.255.255.0" : mask, "text", ""))
    webserver.content_send(self.field("DNS server", "ip4", dhcp ? "" : dns, "text", "placeholder='192.168.1.1'"))
    webserver.content_send("<p><small>The Wi-Fi network itself is changed from Configuration &rarr; Wi-Fi.</small></p></fieldset><p></p>")

    # ---- MQTT ----
    var mq_state = mqtt.connected() ? "connected" : "not connected"
    webserver.content_send(f"<fieldset><legend><b>&nbsp;MQTT&nbsp;</b></legend><p>Status: <b>{mq_state}</b></p>")
    webserver.content_send(self.field("Server", "mh", self.cmd_val("MqttHost"), "text", "placeholder='192.168.1.10 or broker.example.com'"))
    webserver.content_send(self.field("Port", "mp", self.cmd_val("MqttPort"), "number", "min='1' max='65535'"))
    webserver.content_send(self.field("User", "mu", self.cmd_val("MqttUser"), "text", ""))
    webserver.content_send(self.field("Password (empty = unchanged)", "mw", "", "password", "autocomplete='new-password'"))
    webserver.content_send(self.field("Topic", "mt", self.cmd_val("Topic"), "text", ""))
    var c_tls = self.tls_on() ? " checked" : ""
    webserver.content_send(f"<p><label><input type='checkbox' name='ms'{c_tls}> Use TLS (encrypted, usually port 8883; certificate checked against Let's Encrypt and AWS roots)</label></p>")
    webserver.content_send("<p><small>Data is published every TelePeriod seconds to <code>tele/&lt;topic&gt;/SENSOR</code>, key <code>Growatt</code>.</small></p>")
    webserver.content_send("<button name='mqtest' class='button bgrn' formnovalidate>Test server</button></fieldset><p></p>")

    # ---- Modbus ----
    webserver.content_send("<fieldset><legend><b>&nbsp;Inverter / Modbus&nbsp;</b></legend>")
    webserver.content_send(self.field("Inverter Modbus address", "ma", self.addr, "number", "min='1' max='247'"))
    webserver.content_send(self.field("Read every (seconds)", "pi", self.poll_s, "number", "min='2' max='3600'"))
    webserver.content_send(self.field("Modbus TCP port (0 = off)", "tp", self.tcp_port, "number", "min='0' max='65535'"))
    var c_tw = self.tcp_write ? " checked" : ""
    webserver.content_send(f"<p><label><input type='checkbox' name='tw'{c_tw}> Allow Modbus TCP clients to <b>write</b> inverter settings</label></p>")
    var c_sw = self.set_write ? " checked" : ""
    webserver.content_send(f"<p><label><input type='checkbox' name='sw'{c_sw}> Allow inverter settings changes from Home Assistant (MQTT command <code>GrowattSet</code>)</label><br>")
    webserver.content_send("<small>Only the settings in the dongle's safe list, within the manual's limits; each change is read back from the inverter.</small></p>")
    if self.last_set != nil
      var ls = self.last_set
      webserver.content_send(f"<p><small>Last change: {self.esc(ls['Name'])} = {self.esc(ls['Value'])} &middot; {self.esc(ls['Message'])}</small></p>")
    end
    webserver.content_send(f"<p><small>Reads OK: {self.polls_ok}, failed: {self.polls_err} &middot; TCP requests: {self.tcp_req}, no answer: {self.tcp_err}</small></p>")
    webserver.content_send("</fieldset><p></p>")

    webserver.content_send("<button name='save' class='button bgrn'>Save</button></form>")
    webserver.content_button(webserver.BUTTON_MAIN)
    webserver.content_stop()
  end

  def tls_on()
    return string.find(self.cmd_val("SetOption103"), "ON") >= 0
  end

  def valid_ip(s)
    var p = string.split(s, ".")
    if size(p) != 4 return false end
    for x: p
      if size(x) == 0 || size(x) > 3 return false end
      var n = int(x)
      if str(n) != x || n < 0 || n > 255 return false end
    end
    return true
  end

  def page_post()
    if !webserver.check_privileged_access() return nil end

    if webserver.has_arg("mqtest")
      var host = webserver.arg("mh")
      var port = int(webserver.arg("mp"))
      var ok = false
      if size(host) > 0 && port > 0
        var t = tcpclient()
        ok = t.connect(host, port, 3000)
        t.close()
      end
      self.page(ok ? f"Server {self.esc(host)}:{port} is reachable. Press Save to use it."
                   : f"Server {self.esc(host)}:{port} is NOT reachable from the dongle.")
      return
    end

    var restart = false
    if webserver.arg("ipm") == "static"
      if !(self.valid_ip(webserver.arg("ip1")) && self.valid_ip(webserver.arg("ip2")) &&
           self.valid_ip(webserver.arg("ip3")) && self.valid_ip(webserver.arg("ip4")))
        self.page("Nothing saved: for a static address every network field must look like 192.168.1.50.")
        return
      end
    end
    # device
    var dn = webserver.arg("dn")
    if size(dn) > 0 && dn != self.cmd_val("DeviceName")
      tasmota.cmd("DeviceName " + dn, true)
      tasmota.cmd("FriendlyName1 " + dn, true)
    end
    var wp = webserver.arg("wp")
    if size(wp) > 0 tasmota.cmd("WebPassword " + wp, true) end

    # network
    if webserver.arg("ipm") == "static"
      var ip1 = webserver.arg("ip1")
      var ip2 = webserver.arg("ip2")
      var ip3 = webserver.arg("ip3")
      var ip4 = webserver.arg("ip4")
      if ip1 != self.ip_only(self.cmd_val("IPAddress1"))
        tasmota.cmd("IPAddress2 " + ip2, true)
        tasmota.cmd("IPAddress3 " + ip3, true)
        tasmota.cmd("IPAddress4 " + ip4, true)
        tasmota.cmd("IPAddress1 " + ip1, true)
        restart = true
      end
    elif self.ip_only(self.cmd_val("IPAddress1")) != "0.0.0.0"
      tasmota.cmd("IPAddress1 0.0.0.0", true)
      restart = true
    end

    # Modbus (before MQTT, which may reconnect)
    self.addr = int(webserver.arg("ma"))
    self.poll_s = int(webserver.arg("pi"))
    if self.poll_s < 2 self.poll_s = 2 end
    var tp = int(webserver.arg("tp"))
    self.tcp_write = webserver.has_arg("tw")
    self.set_write = webserver.has_arg("sw")
    persist.gw_set_write = self.set_write
    persist.gw_addr = self.addr
    persist.gw_poll = self.poll_s
    persist.gw_tcp_write = self.tcp_write
    if tp != self.tcp_port
      persist.gw_tcp_port = tp
      restart = true
    end
    persist.save()

    # MQTT
    var mh = webserver.arg("mh")
    if mh != self.cmd_val("MqttHost") tasmota.cmd("MqttHost " + mh, true) end
    var mp = webserver.arg("mp")
    if size(mp) > 0 && mp != self.cmd_val("MqttPort") tasmota.cmd("MqttPort " + mp, true) end
    var mu = webserver.arg("mu")
    if mu != self.cmd_val("MqttUser") tasmota.cmd("MqttUser " + (size(mu) > 0 ? mu : "0"), true) end
    var mw = webserver.arg("mw")
    if size(mw) > 0 tasmota.cmd("MqttPassword " + mw, true) end
    var mt = webserver.arg("mt")
    if size(mt) > 0 && mt != self.cmd_val("Topic") tasmota.cmd("Topic " + mt, true) end
    var tls = webserver.has_arg("ms")
    if tls != self.tls_on()
      tasmota.cmd("SetOption132 " + (tls ? "1" : "0"), true)   # check the server against the built-in CAs
      tasmota.cmd("SetOption103 " + (tls ? "1" : "0"), true)   # TLS is applied after a restart
      restart = true
    end

    if restart
      self.page("Saved. The dongle restarts now; with a new address, open it at that address in about 20 seconds.")
      tasmota.set_timer(1500, / -> tasmota.cmd("Restart 1"))
    else
      self.page("Saved.")
    end
  end
end

growatt = GrowattDongle()
