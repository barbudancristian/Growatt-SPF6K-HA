# Reference: Modbus registers

Growatt SPF off-grid protocol, as read by `dongle/growatt.be`. Checked against a capture of three SPF 6000 ES Plus in parallel (firmware 100.06 / 100.08). The same registers can be read by any Modbus TCP client through the dongle (unit ID 1).

| Link | Value |
| --- | --- |
| Physical | inverter USB → CH340 on the stick → ESP32-C3 GPIO0 (TX) / GPIO1 (RX) |
| Serial | 115200 baud, 8N1 |
| Modbus | RTU, slave address 1; reads with function 04 (input) and 03 (holding), writes with 06 |

What the dongle reads:

| Every read (10 s) | Once a minute |
| --- | --- |
| input 0–44, 45–89, 200–249 (BMS) | holding 0–44, 45–89, 90–128; input 96–97 |

32-bit values use two registers, high word first.

## Input registers (function 04)

| Address | Value | Type | Scale |
| --- | --- | --- | --- |
| 0 | Inverter status (see below) | U16 | – |
| 1 / 2 | PV1 / PV2 voltage | U16 | 0.1 V |
| 3 / 5 | PV1 / PV2 power | U32 | 0.1 W |
| 7 / 8 | PV1 / PV2 current | U16 | 0.1 A |
| 9 | Output active power (load) | U32 | 0.1 W |
| 11 | Output apparent power | U32 | 0.1 VA |
| 13 / 15 | AC charge power / apparent power | U32 | 0.1 W / VA |
| 17 | Battery voltage | U16 | 0.01 V |
| 18 | Battery SOC | U16 | 1 % |
| 19 | Bus voltage | U16 | 0.1 V |
| 20 / 21 | Grid voltage / frequency | U16 | 0.1 V / 0.01 Hz |
| 22 / 23 | Output voltage / frequency | U16 | 0.1 V / 0.01 Hz |
| 25 / 26 | Inverter / DC-DC temperature | U16 | 0.1 °C |
| 27 | Inverter load | U16 | 0.1 % |
| 32 / 33 | MPPT 1 / MPPT 2 temperature | U16 | 0.1 °C |
| 34 / 35 | Output current / inverter current | U16 | 0.1 A |
| 36 / 38 | AC input power / apparent power | U32 | 0.1 W / VA |
| 40 / 41 | Fault / warning bits | U16 | bit field |
| 42 / 43 | Fault / warning code | U16 | code |
| 44 | Device type (DTC, 20006) | U16 | – |
| 48 / 50 | PV energy today / total (all PV inputs together) | U32 | 0.1 kWh |
| 56 / 58 | Battery charged from AC today / total | U32 | 0.1 kWh |
| 60 / 62 | Battery discharge today / total | U32 | 0.1 kWh |
| 64 / 66 | Load supplied from AC (bypass) today / total | U32 | 0.1 kWh |
| 68 | AC charge current | U16 | 0.1 A |
| 69 / 71 | Load from AC power / apparent power | U32 | 0.1 W / VA |
| 73 / 75 | Battery discharge power / apparent power | U32 | 0.1 W / VA |
| 77 | Battery power (+ discharging, − charging) | S32 | 0.1 W |
| 81 / 82 | MPPT fan / inverter fan | U16 | 1 % |
| 83 / 84 | Battery charge / discharge current | U16 | 0.1 A |
| 85 / 87 | Load energy today / total | U32 | 0.1 kWh |
| 96 / 97 | Generator power / voltage | U16 | 1 W / 0.1 V |

On the SPF 6000 ES Plus, registers 52/54 (PV2 energy) stay at 0 even when PV2 produces (48/50 count all PV), and 28–31 read 0.

Status codes (register 0): 0 Standby · 2 Discharge · 3 Fault · 4 Firmware update · 5 PV charge · 6 AC charge · 7 Combined charge · 8 Combined charge + bypass · 9 PV charge + bypass · 10 AC charge + bypass · 11 Bypass · 12 PV charge + discharge.

### BMS (input 200–249, only on the inverter wired to the battery)

| Address | Value | Scale |
| --- | --- | --- |
| 200 / 201 / 202 | BMS status / error / warning | code |
| 203 | SOC | 1 % |
| 204 | Voltage | 0.01 V |
| 205 | Current (signed, − discharging) | 0.1 A |
| 206 | Temperature | 0.1 °C |
| 207 / 208 | Charge current / voltage asked by the BMS | 0.01 A / 0.01 V |
| 237 | State of health | 1 % |
| 241 | Cycles (U32) | 1 |
| 243 / 244 | Highest / lowest cell voltage | 1 mV |

## Holding registers (function 03)

| Address | Setting | Values | Dongle |
| --- | --- | --- | --- |
| 0 | Remote on/off | 0 / 1 | read only |
| 1 | Output source priority | 0 SBU · 1 SOL · 2 UTI · 3 SUB | writable |
| 2 | Charger source priority | 0 Solar first · 1 Solar + utility · 2 Solar only | writable |
| 3 / 4 | Grid output start / stop hour | 0–23 | writable |
| 5 / 6 | Grid charge start / stop hour | 0–23 | writable |
| 8 | AC input range | 0 APL · 1 UPS · 2 GEN | writable |
| 9–11 / 12–14 | Firmware / control firmware | ASCII | read |
| 18 / 19 | Output voltage / frequency | 0 208 · 1 230 · 2 240 · 3 220 · 4 100 · 5 110 · 6 120 V / 0 50 · 1 60 Hz | read only |
| 20 / 21 | Overload / over-temperature restart | 0–2 / 0–1 | writable |
| 22 | Buzzer | 0 off · 1 on | writable |
| 23–27 | Serial number | ASCII | read |
| 34 | Max charge current | 10–150 A | writable |
| 35 / 36 | Absorption / float voltage | 0.1 V, 48.0–58.4 | writable |
| 37 | Switch to grid at | 0.1 % (lithium) / 0.1 V (lead) | writable (lithium) |
| 38 | Max grid charge current | 0–80 A | writable |
| 39 | Battery type | 0 AGM · 1 Flooded · 2 User · 3 Lithium · 4 User 2 | read only |
| 43 | Device type | 20006 | read |
| 45–50 | Clock: year, month, day, hour, minute, second | – | `GrowattClock` |
| 76 / 78 | Rated apparent / active power | U32, 0.1 VA / W | read |
| 82 | Battery cut-off at | 0.1 % (lithium) | writable (lithium) |
| 83 | Max generator charge current | 0–80 A | writable |
| 95 | Back to battery at | 0.1 % (lithium) | writable (lithium) |
| 116 | Energy priority | 0 BLU · 1 LBU (firmware 100.08+) | writable |

"Writable" means through the `GrowattSet` MQTT command, after it is allowed on the dongle's settings page. On lithium batteries with a BMS the inverter may follow the BMS limits instead of H34–H36.

## Sources

- [Growatt Local Modbus integration, off-grid register map](https://github.com/WouterTuinstra/Homeassistant-Growatt-Local-Modbus)
- [0xAHA/Growatt_ModbusTCP](https://github.com/0xAHA/Growatt_ModbusTCP): SPF 3000–6000 ES Plus settings registers, BLU/LBU in issue #437
- A passive capture of three SPF 6000 ES Plus in parallel (October 2026)
