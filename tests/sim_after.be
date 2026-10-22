
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
