# Simulated device environment: fake inverter, serial port, TCP and web server.
# Run with tests/run.sh
import string
import json
_now = 0

# ---------------- simulated inverter ----------------
INP = {}
for i: 0..249 INP[i] = 0 end
INP[0]=5 INP[1]=0 INP[2]=2456 INP[5]=0 INP[6]=1610 INP[8]=6 INP[9]=0 INP[10]=1430
INP[11]=0 INP[12]=3120 INP[17]=5190 INP[18]=21 INP[19]=4550 INP[22]=2315 INP[23]=5004 INP[25]=248 INP[26]=218 INP[27]=24 INP[34]=13
INP[48]=0 INP[49]=2 INP[50]=0 INP[51]=5023 INP[56]=0 INP[57]=0 INP[58]=0 INP[59]=41 INP[60]=0 INP[61]=3 INP[62]=0 INP[63]=2062
INP[20]=2231 INP[21]=4998 INP[13]=0 INP[14]=850 INP[64]=0 INP[65]=27 INP[66]=0 INP[67]=1830
INP[73]=0 INP[74]=0 INP[83]=73 INP[84]=0 INP[36]=0 INP[37]=1234 INP[32]=319 INP[82]=13 INP[96]=0 INP[97]=0
# BMS (inverter 1 in the documentation)
INP[200]=103 INP[203]=25 INP[204]=5137 INP[205]=65505 INP[206]=245 INP[207]=14500 INP[208]=5600 INP[237]=100 INP[241]=0 INP[242]=192 INP[243]=3214 INP[244]=3207
INP[77]=0xFFFF INP[78]=0xFBC0 INP[85]=0 INP[86]=4 INP[87]=0 INP[88]=3548
HOLD = {}
for i: 0..128 HOLD[i] = 0 end
HOLD[1]=0 HOLD[2]=2 HOLD[34]=48 HOLD[39]=3 HOLD[35]=560 HOLD[36]=560 HOLD[37]=200 HOLD[38]=30 HOLD[82]=150 HOLD[95]=250
HOLD[8]=1 HOLD[18]=1 HOLD[22]=1 HOLD[20]=1 HOLD[21]=1 HOLD[43]=20006 HOLD[78]=0 HOLD[79]=60000
HOLD[9]=0x3130 HOLD[10]=0x302E HOLD[11]=0x3036 HOLD[12]=0x3130 HOLD[13]=0x312E HOLD[14]=0x3035
HOLD[23]=0x5559 HOLD[24]=0x4E36 HOLD[25]=0x4633 HOLD[26]=0x4430 HOLD[27]=0x3137
HOLD[45]=2102 HOLD[46]=10 HOLD[47]=22 HOLD[48]=11 HOLD[49]=19 HOLD[50]=58
REFUSE = {}
PUBS = {}
SER_WRITES = []

def crc(b)
  var c = 0xFFFF
  for i: 0..size(b)-1
    c ^= b[i]
    for j: 0..7
      if (c & 1) != 0 c = (c >> 1) ^ 0xA001 else c = c >> 1 end
    end
  end
  return c
end

class serial
  static SERIAL_8N1 = 0x800001c
  var rx, silent
  def init(rx, tx, baud, mode) self.rx = bytes() self.silent = false end
  def available() return size(self.rx) end
  def read() var r = self.rx self.rx = bytes() return r end
  def write(f)
    SER_WRITES.push(f)
    if self.silent return end
    var a = f[0] var fc = f[1] var st = f.get(2,-2) var n = f.get(4,-2)
    var r = bytes()
    r.add(a,1)
    if fc == 3 || fc == 4
      var m = fc == 4 ? INP : HOLD
      r.add(fc,1) r.add(n*2,1)
      for i: 0..n-1 r.add(m.find(st+i,0),-2) end
    elif fc == 6 && REFUSE.find(st) == nil
      HOLD[st] = n
      r.add(fc,1) r.add(st,-2) r.add(n,-2)
    elif fc == 6
      r.add(0x86,1) r.add(3,1)
    else
      r.add(fc|0x80,1) r.add(1,1)
    end
    r.add(crc(r),2)
    self.rx = r
  end
end

class FakeClient
  var inb, outb, open
  def init() self.inb = bytes() self.outb = bytes() self.open = true end
  def connected() return self.open end
  def available() return size(self.inb) end
  def readbytes() var r = self.inb self.inb = bytes() return r end
  def write(b) self.outb = self.outb + b end
  def close() self.open = false end
  def connect(h, p, t) return h == "good" end
end
tcpclient = FakeClient
PENDING = []
class tcpserver
  def init(port) end
  def hasclient() return size(PENDING) > 0 end
  def accept() var c = PENDING[0] PENDING.remove(0) return c end
end

class TasStub
  var drivers, fast, resp, sent, st, cmds
  def init()
    self.drivers = [] self.fast = [] self.resp = "" self.sent = "" self.cmds = []
    self.st = {"IPAddress1":"0.0.0.0 (192.168.1.57)","IPAddress2":"192.168.1.1","IPAddress3":"255.255.255.0","IPAddress4":"192.168.1.1",
               "DeviceName":"DongleGrowatt","MqttHost":"","MqttPort":"1883","MqttUser":"DVES_USER","Topic":"DongleGrowatt_ABC"}
  end
  def millis() return _now end
  def log(m, l) print("  LOG:", m) end
  def add_driver(d) self.drivers.push(d) end
  def add_fast_loop(f) self.fast.push(f) end
  def is_network_up() return true end
  def response_append(s) self.resp += s end
  def web_send(s) self.sent += s end
  def wifi() return {"ip":"192.168.1.57","up":true} end
  def set_timer(ms, f) self.cmds.push("TIMER") end
  var ucmds, lastresp
  def add_cmd(n, f) if self.ucmds == nil self.ucmds = {} end self.ucmds[n] = f end
  def resp_cmnd(s) self.lastresp = s end
  def rtc() return {"local": 1792750000} end
  def time_dump(t) return {"year":2026,"month":10,"day":23,"hour":14,"min":5,"sec":9} end
  def run_cmd(n, payload) self.ucmds[n](n, 0, payload) return json.load(self.lastresp) end
  def cmd(c, mute)
    self.cmds.push(c)
    var p = string.find(c, " ")
    if p > 0
      var k = c[0..p-1] var v = c[p+1..]
      self.st[k] = v
      return {k: v}
    end
    return {c: self.st.find(c, "")}
  end
end
tasmota = TasStub()

def run(ms)
  var end_t = _now + ms
  while _now < end_t
    _now += 5
    for f: tasmota.fast f() end
  end
end

