# DongleGrowatt – Growatt SPF to MQTT and Modbus TCP

Firmware for the Growatt **ShineWiFi-X2** stick that turns it into a local gateway for Growatt **SPF** off-grid inverters. Flash it once, then set everything up from a web page: Wi-Fi, static or automatic address, MQTT server, device name and admin password. No cloud, no compiling.

> **Română:** [README.ro.md](README.ro.md) · [Ghid pas cu pas](docs/GHID.ro.md)

## What it does

- **Reads the inverter** every 10 seconds over the stick's USB link: PV strings, battery (SOC, voltage, power), AC output, temperatures, status, fault and warning codes, daily and total energy, inverter settings.
- **Sends the data to your MQTT server** as one JSON message (`tele/<topic>/SENSOR`), with or without TLS. A ready-made Home Assistant package creates 35 sensors.
- **Modbus TCP gateway** on port 502: Home Assistant, Node-RED or any Modbus TCP client can read the inverter through the dongle. Requests are queued with the dongle's own reads. Writing settings is off unless you enable it.
- **Setup hotspot** `DongleGrowatt-xxxx` on first start, to choose the Wi-Fi network from a phone.
- **Settings page** with network (DHCP or static), MQTT with a **Test server** button, device name, admin password and Modbus options.
- **Status page** with the live inverter values, and firmware updates from the browser.

## Hardware

| | |
| --- | --- |
| Stick | Growatt ShineWiFi-X2, board B700.0198800 |
| Module | Ai-Thinker ESP-C3-13U (ESP32-C3, 4 MB flash) |
| Inverter link | USB → CH340 → GPIO0 (TX) / GPIO1 (RX), 115200 8N1, Modbus address 1 |
| Inverter | Growatt SPF 6000 ES Plus; other SPF models with the same off-grid protocol should work |

## Quick start

1. Download `DongleGrowatt.factory.bin` from **Releases** (or the latest **Actions** build).
2. Open the stick, wire a 3.3 V USB-TTL adapter to the header, bridge IO9 to G.
3. Check that Secure Boot and Flash Encryption are disabled and **back up the Growatt firmware**.
4. Flash `DongleGrowatt.factory.bin`.
5. Join the **DongleGrowatt-xxxx** hotspot (password `donglegrowatt`) and choose your Wi-Fi.
6. Open the dongle in a browser → **Dongle settings**: set the admin password, network and MQTT server.
7. Plug the stick into the inverter.

Full instructions: **[docs/GUIDE.en.md](docs/GUIDE.en.md)**.

## Repository

| Path | Content |
| --- | --- |
| `dongle/growatt.be` | the driver: Modbus RTU polling, MQTT data, Modbus TCP gateway, settings page |
| `dongle/autoexec.be` | starts the driver at boot |
| `build/` | build settings (name, hotspot, defaults) |
| `.github/workflows/build.yml` | tests the driver, builds the firmware, publishes it |
| `tests/` | runs the driver against a simulated inverter |
| `homeassistant/donglegrowatt.yaml` | Home Assistant MQTT sensors |
| `docs/` | guide (English, Romanian) and register reference |

## Status

The driver is tested against a simulated inverter on every build (Modbus framing and CRC, decoding, TCP gateway, timeouts, settings page). Testing on a real stick and inverter is in progress; report problems under **Issues**.

## Safety

You modify your own hardware at your own risk. Keep the backup of the original firmware; with it you can always restore the stick. Never connect 5 V to the stick's header.

## Credits and license

Author: **Barbu Dan-Cristian**.

DongleGrowatt is built on the open-source [Tasmota](https://github.com/arendst/Tasmota) firmware by Theo Arends and contributors, and is released under the same **GNU GPL v3.0** license. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

Not affiliated with Growatt. Growatt, ShineWiFi and SPF are trademarks of their owners.
