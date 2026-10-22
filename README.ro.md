# DongleGrowatt – de la Growatt SPF la MQTT și Modbus TCP

Firmware pentru stick-ul Growatt **ShineWiFi-X2** care îl transformă într-o punte locală pentru invertoarele off-grid Growatt **SPF**. Îl scrii o singură dată, apoi setezi totul dintr-o pagină web: Wi-Fi, adresă statică sau automată, server MQTT, nume și parolă de admin. Fără cloud, fără compilare.

> **English:** [README.md](README.md) · [Step-by-step guide](docs/GUIDE.en.md)

## Ce face

- **Citește invertorul** la fiecare 10 secunde, prin legătura USB a stick-ului: panourile PV, bateria (SOC, tensiune, putere), ieșirea AC, temperaturile, starea, codurile de eroare și avertizare, energia pe zi și totală, setările invertorului.
- **Trimite datele la serverul tău MQTT** ca un singur mesaj JSON (`tele/<topic>/SENSOR`), cu sau fără TLS. Un pachet gata făcut pentru Home Assistant creează 35 de senzori.
- **Punte Modbus TCP** pe portul 502: Home Assistant, Node-RED sau orice client Modbus TCP poate citi invertorul prin dongle. Cererile sunt puse la rând cu citirile proprii ale dongle-ului. Scrierea setărilor e oprită, dacă nu o activezi.
- **Hotspot de configurare** `DongleGrowatt-xxxx` la prima pornire, ca să alegi rețeaua Wi-Fi de pe telefon.
- **Pagină de setări**: rețea (DHCP sau statică), MQTT cu buton **Test server**, nume, parolă de admin și opțiuni Modbus.
- **Pagină de stare** cu valorile live ale invertorului, plus actualizări de firmware din browser.

## Hardware

| | |
| --- | --- |
| Stick | Growatt ShineWiFi-X2, placa B700.0198800 |
| Modul | Ai-Thinker ESP-C3-13U (ESP32-C3, flash 4 MB) |
| Legătura cu invertorul | USB → CH340 → GPIO0 (TX) / GPIO1 (RX), 115200 8N1, adresa Modbus 1 |
| Invertor | Growatt SPF 6000 ES Plus; alte modele SPF cu același protocol off-grid ar trebui să meargă |

## Pe scurt

1. Descarci `DongleGrowatt.factory.bin` din **Releases** (sau ultima compilare din **Actions**).
2. Deschizi stick-ul, legi un adaptor USB-TTL pe 3,3 V la header și unești IO9 cu G.
3. Verifici că Secure Boot și Flash Encryption sunt dezactivate și **faci backup la firmware-ul Growatt**.
4. Scrii `DongleGrowatt.factory.bin`.
5. Te conectezi la hotspotul **DongleGrowatt-xxxx** (parola `donglegrowatt`) și alegi rețeaua Wi-Fi.
6. Deschizi dongle-ul în browser → **Dongle settings**: parola de admin, rețeaua și serverul MQTT.
7. Bagi stick-ul în invertor.

Instrucțiunile complete: **[docs/GHID.ro.md](docs/GHID.ro.md)**.

## Conținutul repository-ului

| Cale | Conținut |
| --- | --- |
| `dongle/growatt.be` | programul: citirea Modbus RTU, datele MQTT, puntea Modbus TCP, pagina de setări |
| `dongle/autoexec.be` | pornește programul la boot |
| `build/` | setările de compilare (nume, hotspot, valori implicite) |
| `.github/workflows/build.yml` | testează programul, compilează firmware-ul și îl publică |
| `tests/` | rulează programul pe un invertor simulat |
| `homeassistant/donglegrowatt.yaml` | senzorii MQTT pentru Home Assistant |
| `docs/` | ghidul (română, engleză) și lista registrelor |

## Stadiu

La fiecare compilare, programul e testat pe un invertor simulat (cadre Modbus și CRC, decodare, puntea TCP, timeout-uri, pagina de setări). Testarea pe un stick și un invertor reale e în curs; problemele le raportezi la **Issues**.

## Siguranță

Modifici propriul hardware, pe propriul risc. Păstrează backup-ul firmware-ului original: cu el poți readuce oricând stick-ul la starea din fabrică. Nu lega niciodată 5 V la header-ul stick-ului.

## Credite și licență

Autor: **Barbu Dan-Cristian**.

DongleGrowatt e construit pe firmware-ul open-source [Tasmota](https://github.com/arendst/Tasmota), de Theo Arends și colaboratorii lui, și e publicat sub aceeași licență **GNU GPL v3.0**. Vezi [LICENSE](LICENSE) și [NOTICE](NOTICE).

Proiectul nu e afiliat cu Growatt. Growatt, ShineWiFi și SPF sunt mărci ale proprietarilor lor.
