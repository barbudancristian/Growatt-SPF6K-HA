# DongleGrowatt – de la Growatt SPF la MQTT și Modbus TCP

Firmware pentru stick-ul Growatt **ShineWiFi-X2** care îl transformă într-o punte locală pentru invertoarele off-grid Growatt **SPF**. Îl scrii o singură dată, apoi setezi totul dintr-o pagină web: Wi-Fi, adresă statică sau automată, server MQTT, nume și parolă de admin. Fără cloud, fără compilare.

> **English:** [README.md](README.md) · [Step-by-step guide](docs/GUIDE.en.md)

## Ce face

- **Citește invertorul** la fiecare 10 secunde, prin legătura USB a stick-ului: panourile PV, bateria (SOC, tensiune, putere), ieșirea AC, temperaturile, starea, codurile de eroare și avertizare, energia pe zi și totală, setările invertorului.
- **Trimite datele la serverul tău MQTT** ca un singur mesaj JSON (`tele/<topic>/SENSOR`), cu sau fără TLS. Pachete gata făcute pentru Home Assistant (1 sau 3 invertoare) și o pagină de dashboard.
- **Punte Modbus TCP** pe portul 502: Home Assistant, Node-RED sau orice client Modbus TCP poate citi invertorul prin dongle. Cererile sunt puse la rând cu citirile proprii ale dongle-ului. Scrierea setărilor e oprită, dacă nu o activezi.
- **Hotspot de configurare** `DongleGrowatt-xxxx` la prima pornire, ca să alegi rețeaua Wi-Fi de pe telefon.
- **Pagină de setări**: rețea (DHCP sau statică), MQTT cu buton **Test server**, nume, parolă de admin și opțiuni Modbus.
- **Pagină de stare** cu valorile live ale invertorului, plus actualizări de firmware din browser.

## Dashboard Home Assistant

O pagină de dashboard gata făcută arată tot sistemul dintr-o privire. Citește senzorii creați de pachetele din `homeassistant/packages/` și se adaugă în Home Assistant ca un card **Webpage** (vezi [ghidul](docs/GHID.ro.md#dashboard)). Design: Andrei Cristetiu.

### Trei invertoare, cu rețea

<img src="docs/img/dashboard-3.png" width="820" alt="Dashboard pentru trei invertoare Growatt">

`homeassistant/dashboard/solar-3-inverters.html`, de exemplu câte un invertor pe fiecare fază (L1, L2, L3):

- **Fluxul de energie** (stânga sus): soarele, rețeaua, casa și bateria în jurul celor trei invertoare, cu linii animate în sensul în care circulă puterea. Inelul bateriei arată SOC-ul mediu.
- **Economii** (caseta din stânga sus): banii economisiți în total, luna asta și azi, la prețul setat în pagină (RON/kWh).
- **Azi** (dreapta sus): producția, consumul, descărcarea bateriei și încărcarea din rețea, plus starea bateriei, puterea, tensiunea, timpul rămas și ora la care va fi goală sau plină.
- **Câte un card pentru fiecare invertor**: puterea de ieșire și bara de încărcare, PV1/PV2, bateria, SOC-ul, rețeaua, tensiunea de ieșire, temperatura, producția de azi și starea invertorului (de exemplu „PV + bypass”).
- **Puterea în timp**: zi, 24 h, 48 h sau lună; curbele pentru soare, consum, baterie și rețea, cu prognoza solară punctată; plăcuțe cu producția reală, consumul, prognoza și economiile. Vederea pe lună arată bare pe zile, în kWh sau RON.

### Un invertor off-grid

<img src="docs/img/dashboard-1.png" width="820" alt="Dashboard pentru un invertor Growatt off-grid">

`homeassistant/dashboard/solar-1-inverter.html`, pentru un singur invertor fără rețea (de exemplu la o cabană): aceeași pagină, fără rețea în flux, în plăcuțe și în grafic, și cu un singur card lat pentru invertor.

Ambele pagini se setează din blocul `CONFIG` de la începutul fișierului (titlu, număr de invertoare, cu sau fără rețea, prețul energiei). Plăcuțele cu prognoza au nevoie de integrarea Forecast.Solar. Capturile arată date de exemplu.

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
| `homeassistant/packages/` | senzorii Home Assistant pentru 1 sau 3 invertoare, plus senzorii de sumar |
| `homeassistant/dashboard/` | paginile de dashboard Home Assistant (1 invertor off-grid, 3 invertoare cu rețea) |
| `tools/ha_package.py` | generează pachetul Home Assistant pentru orice număr de invertoare |
| `docs/` | ghidul (română, engleză) și lista registrelor |

## Stadiu

La fiecare compilare, programul e testat pe un invertor simulat (cadre Modbus și CRC, decodare, puntea TCP, timeout-uri, pagina de setări). Testarea pe un stick și un invertor reale e în curs; problemele le raportezi la **Issues**.

## Siguranță

Modifici propriul hardware, pe propriul risc. Păstrează backup-ul firmware-ului original: cu el poți readuce oricând stick-ul la starea din fabrică. Nu lega niciodată 5 V la header-ul stick-ului.

## Credite și licență

Autor: **Barbu Dan-Cristian**.

Dashboard-ul pentru Home Assistant e bazat pe pagina originală a lui **Andrei Cristetiu**.

DongleGrowatt e construit pe firmware-ul open-source [Tasmota](https://github.com/arendst/Tasmota), de Theo Arends și colaboratorii lui, și e publicat sub aceeași licență **GNU GPL v3.0**. Vezi [LICENSE](LICENSE) și [NOTICE](NOTICE).

Proiectul nu e afiliat cu Growatt. Growatt, ShineWiFi și SPF sunt mărci ale proprietarilor lor.
