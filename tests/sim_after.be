
# ---------------- assertions ----------------
def check(cond, msg) if !cond print("FAIL:", msg) raise "test_failed", msg end print("ok  ", msg) end
var g = growatt
print("--- poll")
run(4000)
print("writes:", size(SER_WRITES), SER_WRITES)
g.every_second()
tasmota.resp = ""
g.json_append()
print(tasmota.resp)
var v = json.load("{" + tasmota.resp[1..] + "}")
print("SOC", v["Growatt"]["Battery"]["SOC"], "BattPower", v["Growatt"]["Battery"]["Power"], "PV2", v["Growatt"]["PV2"])
tasmota.sent = ""
g.web_sensor()
print(tasmota.sent)

print("--- modbus TCP read input 17..18")
var c = FakeClient()
PENDING.push(c)
var req = bytes("00070000000601040011 0002")
c.inb = bytes("000700000006010400110002")
run(200)
print("tcp reply:", c.outb)
print("--- modbus TCP write refused")
c.outb = bytes()
c.inb = bytes("0008000000060106002200 10")
c.inb = bytes("000800000006010600220010")
run(100)
print("tcp reply:", c.outb)
print("--- two frames in one packet")
c.outb = bytes()
c.inb = bytes("000900000006010300010001") + bytes("000A00000006010300270001")
run(300)
print("tcp reply:", c.outb)

print("--- timeout")
var s = g.ser
s.silent = true
c.outb = bytes()
c.inb = bytes("000B000000060104000000 01")
c.inb = bytes("000B00000006010400000001")
run(1500)
print("tcp reply:", c.outb, "tcp_err", g.tcp_err)
s.silent = false
run(12000)
print("online after recovery:", g.online())

print("--- settings page GET")
g.web_add_handler()
import webserver
webserver.routes["/gw1"]()
print(size(webserver.out), "chars", string.find(webserver.out, "Static address") > 0)
print("--- POST mqtt test")
webserver.args = {"mqtest":"", "mh":"good", "mp":"1883"}
webserver.routes["/gw2"]()
var p = string.find(webserver.out, "reachable")
print(webserver.out[p-30 .. p+40])
print("--- POST save static")
webserver.args = {"save":"","dn":"Cabana2","wp":"","ipm":"static","ip1":"192.168.1.60","ip2":"192.168.1.1","ip3":"255.255.255.0","ip4":"192.168.1.1",
  "mh":"10.0.0.5","mp":"1883","mu":"user","mw":"pw","mt":"growatt","ma":"1","pi":"10","tp":"502"}
tasmota.cmds = []
webserver.routes["/gw2"]()
print(tasmota.cmds)
print("--- POST invalid ip")
webserver.args["ip1"] = "192.168.1"
tasmota.cmds = []
webserver.routes["/gw2"]()
print(string.find(webserver.out, "Nothing saved") > 0, tasmota.cmds)

check(SER_WRITES[0] == bytes("01040000002D3017"), "poll request frame and CRC")
check(v["Growatt"]["Battery"]["SOC"] == 21, "battery SOC decoded")
check(v["Growatt"]["Battery"]["Power"] < 0, "battery power negative while charging")
check(v["Growatt"]["Settings"]["BatteryType"] == "Lithium", "holding register decoded")
check(growatt.crc16(bytes("010400000007")) == 0xC8B1, "CRC matches a real inverter request")
check(growatt.online(), "inverter back online after a timeout")
check(v["Growatt"]["Grid"]["Voltage"] == 223.1 && v["Growatt"]["Energy"]["ACDischargeTotal"] == 183, "grid and AC discharge decoded")

print("--- extended values")
check(v["Growatt"]["Battery"]["ChargeCurrent"] == 7.3 && v["Growatt"]["Battery"]["DischargeCurrent"] == 0, "battery currents from input 83 / 84")
check(v["Growatt"]["Grid"]["Power"] == 123.4, "grid input power from input 36-37")
var bm = json.load(PUBS["tele/DongleGrowatt_ABC/GROWATT_BMS"])
print(PUBS["tele/DongleGrowatt_ABC/GROWATT_BMS"])
check(bm["SOH"] == 100 && bm["Cycles"] == 192 && bm["Current"] == -3.1 && bm["CellDelta"] == 7, "BMS block decoded")
var inf = json.load(PUBS["tele/DongleGrowatt_ABC/GROWATT_INFO"])
print(PUBS["tele/DongleGrowatt_ABC/GROWATT_INFO"])
check(inf["Serial"] == "UYN6F3D017" && inf["Firmware"] == "100.06" && inf["RatedPower"] == 6000, "serial, firmware, rated power")
check(inf["Clock"] == "2102-10-22 11:19:58", "inverter clock")
var se = inf["Settings"]
check(se["back_to_battery_capacity"] == 25 && se["battery_absorption_charge_voltage"] == 56 && se["output_source_priority"] == "Solar/Battery/Utility", "settings in real units")
check(se["battery_type"] == "Lithium BMS" && se["ac_input_range"] == "UPS", "option texts")
print("sizes: SENSOR", size(tasmota.resp), "INFO", size(PUBS["tele/DongleGrowatt_ABC/GROWATT_INFO"]), "BMS", size(PUBS["tele/DongleGrowatt_ABC/GROWATT_BMS"]))

print("--- settings writes")
growatt.set_write = false
var r = tasmota.run_cmd("GrowattSet", "back_to_battery_capacity 30")
check(r["GrowattSet"]["Result"] == "Error", "refused while writes are off")
growatt.set_write = true
r = tasmota.run_cmd("GrowattSet", "battery_type 0")
check(r["GrowattSet"]["Result"] == "Error", "battery type is read-only")
r = tasmota.run_cmd("GrowattSet", "max_charge_current 500")
check(r["GrowattSet"]["Result"] == "Error", "out of range refused")
r = tasmota.run_cmd("GrowattSet", "max_charge_current abc")
check(r["GrowattSet"]["Result"] == "Error", "not a number refused")
r = tasmota.run_cmd("GrowattSet", "output_source_priority Banana")
check(r["GrowattSet"]["Result"] == "Error", "unknown option refused")
r = tasmota.run_cmd("GrowattSet", "back_to_battery_capacity 30")
check(r["GrowattSet"]["Result"] == "Queued", "valid value queued")
r = tasmota.run_cmd("GrowattSet", "to_grid_battery_capacity 20")
check(r["GrowattSet"]["Result"] == "Error", "second change refused while the first runs")
run(300)
check(HOLD[95] == 300, "H95 written as 300 (30.0 %)")
var ls = json.load(PUBS["tele/growatt/GROWATT_SET"])
check(ls["Result"] == "OK", "result published after read back")
r = tasmota.run_cmd("GrowattSet", "charger_source_priority solar only")
run(300)
check(HOLD[2] == 2 && json.load(PUBS["tele/growatt/GROWATT_SET"])["Result"] == "OK", "option by text, any case")
r = tasmota.run_cmd("GrowattSet", "battery_float_charge_voltage 55.4")
run(300)
check(HOLD[36] == 554, "voltage scaled to 0.1 V")
REFUSE[38] = true
r = tasmota.run_cmd("GrowattSet", "max_grid_charge_current 40")
run(300)
check(HOLD[38] == 30 && json.load(PUBS["tele/growatt/GROWATT_SET"])["Result"] == "Error", "inverter refusal reported")
r = tasmota.run_cmd("GrowattClock", "")
run(500)
check(HOLD[45] == 2026 && HOLD[46] == 10 && HOLD[47] == 23 && HOLD[48] == 14 && HOLD[50] == 9, "clock written")
check(json.load(PUBS["tele/growatt/GROWATT_SET"])["Result"] == "OK", "clock result")
growatt.hold[39] = 0
r = tasmota.run_cmd("GrowattSet", "shutdown_battery_capacity 20")
check(r["GrowattSet"]["Result"] == "Error", "SOC thresholds refused on lead batteries")
print("ALL OK")
