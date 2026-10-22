# Reference: Modbus registers

Growatt SPF off-grid protocol, as read by `dongle/growatt.be`. The dongle reads input registers 0–89 in two requests and holding registers 0–44 once a minute. The same registers can be read by any Modbus TCP client through the dongle (unit ID 1).

| Link | Value |
| --- | --- |
| Physical | inverter USB → CH340 on the stick → ESP32-C3 GPIO0 (TX) / GPIO1 (RX) |
| Serial | 115200 baud, 8N1 |
| Modbus | RTU, slave address 1 |

On the SPF 6000 ES Plus, registers 52/54 (PV2 energy) stay at 0 even when PV2 produces, and register 30 (operating time) reads 0; registers 56/58 count only charging from AC.

## Input registers (function 04)

| Address | Value | Type | Scale |
| --- | --- | --- | --- |
| 0 | Inverter status (see below) | U16 | – |
| 1 / 2 | PV1 / PV2 voltage | U16 | 0.1 V |
| 3 / 5 | PV1 / PV2 power | U32 | 0.1 W |
| 7 / 8 | PV1 / PV2 current | U16 | 0.1 A |
| 9 | Output active power (load) | U32 | 0.1 W |
| 11 | Output apparent power | U32 | 0.1 VA |
| 17 | Battery voltage | U16 | 0.01 V |
| 18 | Battery SOC | U16 | 1 % |
| 19 | Bus voltage | U16 | 0.1 V |
| 22 / 23 | Output voltage / frequency | U16 | 0.1 V / 0.01 Hz |
| 25 / 26 | Inverter / DC-DC temperature | U16 | 0.1 °C |
| 27 | Inverter load | U16 | 0.1 % |
| 34 | Output current | U16 | 0.1 A |
| 42 / 43 | Fault / warning code | U16 | bit field |
| 48 / 50 | PV energy today / total (all PV inputs together) | U32 | 0.1 kWh |
| 56 / 58 | Battery charged from AC (grid/generator) today / total | U32 | 0.1 kWh |
| 60 / 62 | Battery discharge today / total | U32 | 0.1 kWh |
| 73 | Battery discharge current | U16 | 0.1 A |
| 77 | Battery power (+ discharging, − charging) | S32 | 0.1 W |
| 85 / 87 | Load energy today / total | U32 | 0.1 kWh |

Status codes (register 0): 0 Standby · 2 Discharge · 3 Fault · 5 PV charge · 6 AC charge · 7 Combined charge · 8 Combined charge + bypass · 9 PV charge + bypass · 10 AC charge + bypass · 11 Bypass · 12 PV charge + discharge.

## Holding registers (function 03, read once a minute)

| Address | Setting | Values |
| --- | --- | --- |
| 1 | Output source priority | 0 SBU · 1 SOL · 2 UTI · 3 SUB |
| 2 | Charger source priority | 0 Solar first · 1 Solar + utility · 2 Solar only |
| 34 | Max charge current | A |
| 39 | Battery type | 0 AGM · 1 Flooded · 2 User · 3 Lithium · 4 User2 |

The value order of registers 1, 2 and 39 comes from community work ([0xAHA/Growatt_ModbusTCP #444](https://github.com/0xAHA/Growatt_ModbusTCP/issues/444)); compare with your inverter's menu once. The dongle itself only reads; writes happen only if you allow Modbus TCP clients to write.

## Sources

- [Growatt Local Modbus integration, off-grid register map](https://github.com/WouterTuinstra/Homeassistant-Growatt-Local-Modbus)
- [0xAHA/Growatt_ModbusTCP issue #444](https://github.com/0xAHA/Growatt_ModbusTCP/issues/444): SPF holding registers
