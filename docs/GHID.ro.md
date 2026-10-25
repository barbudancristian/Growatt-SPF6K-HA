# DongleGrowatt – ghid pas cu pas (română)

> English: [GUIDE.en.md](GUIDE.en.md)

DongleGrowatt transformă un stick Growatt **ShineWiFi-X2** într-o punte locală pentru un invertor off-grid Growatt **SPF**. Îl scrii o singură dată, apoi totul se setează din browser. Citește invertorul la câteva secunde, trimite valorile la serverul MQTT ales de tine și răspunde la cereri Modbus TCP pe portul 502.

**Cuprins**

1. [De ce ai nevoie](#1-de-ce-ai-nevoie)
2. [Descărcarea firmware-ului](#2-descărcarea-firmware-ului)
3. [Deschiderea stick-ului și conectarea adaptorului](#3-deschiderea-stick-ului-și-conectarea-adaptorului)
4. [Verificarea cipului și backup-ul firmware-ului Growatt](#4-verificarea-cipului-și-backup-ul-firmware-ului-growatt)
5. [Scrierea DongleGrowatt](#5-scrierea-donglegrowatt)
6. [Prima pornire: hotspotul DongleGrowatt](#6-prima-pornire-hotspotul-donglegrowatt)
7. [Pagina „Dongle settings”](#7-pagina-dongle-settings)
8. [Montarea în invertor](#8-montarea-în-invertor)
9. [Datele MQTT](#9-datele-mqtt)
10. [Home Assistant](#10-home-assistant)
11. [Modbus TCP](#11-modbus-tcp)
12. [Actualizări](#12-actualizări)
13. [Depanare](#13-depanare)
14. [Revenirea la firmware-ul Growatt](#14-revenirea-la-firmware-ul-growatt)

---

## 1. De ce ai nevoie

- un stick Growatt ShineWiFi-X2 (placa testată: **B700.0198800**, modul ESP32-C3 ESP-C3-13U);
- un adaptor USB-TTL care merge pe **3,3 V** (CP2102, CH340 sau FT232) și câteva fire dupont;
- un PC cu Python (pe Windows: `winget install Python.Python.3.12`), apoi `python -m pip install esptool`;
- un server MQTT: Mosquitto din Home Assistant, HiveMQ Cloud sau oricare altul.

Nu lega niciodată 5 V la stick, nu rula comenzi `espefuse burn-...` și păstrează backup-ul de la pasul 4. Lucrezi pe propriul risc.

## 2. Descărcarea firmware-ului

Deschide pagina **Releases** a repository-ului și descarcă:

| Fișier | Pentru |
| --- | --- |
| `DongleGrowatt.factory.bin` | prima scriere, prin cablu (conține și scripturile) |
| `DongleGrowatt.bin` | actualizările ulterioare, din pagina web a dongle-ului |
| `growatt.be`, `autoexec.be` | scripturile, dacă le actualizezi separat |

Între versiuni, ultima compilare e la **Actions → Build firmware → (ultima rulare) → Artifacts**.

## 3. Deschiderea stick-ului și conectarea adaptorului

Scoate cele două șuruburi și glisează placa afară. Lângă modulul metalic e un header cu 7 găuri: `3.3V · G · TX0 · RX0 · RST · IO9 · G`.

Scoate stick-ul din invertor și din orice port USB, apoi leagă:

| Adaptor | Stick |
| --- | --- |
| GND | G |
| 3V3 (nu 5V) | 3.3V |
| TXD | RX0 |
| RXD | TX0 |
| — | IO9 legat la G (modul de programare) |

Bagă adaptorul în PC și notează portul (în Windows: Device Manager → Ports, de exemplu `COM7`). Cu puntea IO9 pusă, scoate și bagă la loc adaptorul înainte de **fiecare** comandă esptool de mai jos.

## 4. Verificarea cipului și backup-ul firmware-ului Growatt

```
python -m esptool --chip esp32c3 -p COM7 --before no-reset chip-id
python -m esptool --chip esp32c3 -p COM7 --before no-reset get-security-info
```

Trebuie să apară `ESP32-C3`, **Secure Boot: Disabled** și **Flash Encryption: Disabled**. Dacă oricare e activat, oprește-te.

Citește toată memoria de două ori și compară rezultatele. Comenzile se dau **pe rând, nu toate odată**: adaptorul nu poate reseta cipul (pinul RTS nu e legat), iar după o citire cipul rămâne la viteza de 230400, așa că o a doua comandă dată imediat după prima eșuează.

**a) Primul backup.** Scoate adaptorul din USB, bagă-l la loc, apoi:

```
python -m esptool --chip esp32c3 -p COM7 --before no-reset -b 230400 read-flash 0 ALL stock_backup_1.bin
```

**b) Al doilea backup.** Așteaptă să termine prima citire, scoate din nou adaptorul din USB, bagă-l la loc, apoi:

```
python -m esptool --chip esp32c3 -p COM7 --before no-reset -b 230400 read-flash 0 ALL stock_backup_2.bin
```

**c) Mută-le într-un folder separat și compară-le** (aici nu mai e nevoie de adaptor):

```
mkdir Backup-ShineWiFi-X2
Move-Item stock_backup_1.bin, stock_backup_2.bin Backup-ShineWiFi-X2
Get-FileHash Backup-ShineWiFi-X2\*.bin
```

Cele două hash-uri trebuie să fie identice. Păstrează backup-ul privat: conține parola Wi-Fi și cheile cloud-ului Growatt.

## 5. Scrierea DongleGrowatt

Adaptorul legat, puntea IO9 pusă, adaptorul scos și băgat la loc:

```
python -m esptool --chip esp32c3 -p COM7 --before no-reset -b 230400 write-flash 0x0 DongleGrowatt.factory.bin
```

Sau din Chrome/Edge, pe web.esphome.io: **Connect → portul tău → Install → DongleGrowatt.factory.bin**.

Scoate puntea IO9 și deconectează adaptorul.

## 6. Prima pornire: hotspotul DongleGrowatt

1. Alimentează stick-ul prin mufa lui USB (încărcător de telefon, port de PC sau invertor).
2. Pe telefon, conectează-te la rețeaua **DongleGrowatt-xxxx**, parola **donglegrowatt**.
3. Pagina de configurare se deschide singură; dacă nu, deschide `http://192.168.4.1`. Alegi rețeaua de 2,4 GHz, scrii parola, **Save**.
4. Stick-ul repornește și intră în rețeaua ta. Îi găsești adresa în lista de clienți a routerului (numele `DongleGrowatt-xxxx`) și deschizi `http://<adresa>`.

Dacă rețeaua salvată nu e găsită, hotspotul reapare și poți alege alta.

## 7. Pagina „Dongle settings”

Pe pagina principală a dongle-ului apeși **Dongle settings**. Totul e pe o singură pagină:

| Secțiune | Ce setezi |
| --- | --- |
| Device | **numele dispozitivului** și o **parolă nouă de admin** pentru paginile web (utilizator `admin`). Pune o parolă de la prima folosire. |
| Network | **DHCP** (automat) sau **adresă statică**: IP, gateway, mască, DNS. La salvarea unei adrese noi, dongle-ul repornește. |
| MQTT | server, port, utilizator, parolă, topic, plus **Use TLS** pentru brokerii criptați, cum e HiveMQ Cloud (port 8883; dongle-ul repornește). **Test server** verifică dacă dongle-ul ajunge la acel server și port; **Save** se conectează cu ele. Rândul de stare arată dacă MQTT e conectat. |
| Inverter / Modbus | adresa Modbus a invertorului (1), intervalul de citire (10 s), portul Modbus TCP (502, 0 = oprit), dacă clienții TCP au voie să **scrie** setări și dacă Home Assistant poate **schimba setările invertorului** prin MQTT (ambele oprite implicit). Sub căsuțe vezi ultima modificare și rezultatul ei. |

Câmpurile de parolă lăsate goale păstrează parola actuală. Rețeaua Wi-Fi propriu-zisă se schimbă din **Configuration → Wi-Fi**.

## 8. Montarea în invertor

Bagi stick-ul în portul de dongle al invertorului. În câteva secunde pagina principală arată invertorul: stare, SOC și puterea bateriei, PV, consum, ieșirea AC, temperatura, energia de azi și setările invertorului.

„no answer” înseamnă că invertorul nu răspunde: verifică dacă stick-ul e băgat complet și dacă adresa Modbus e 1. Contoarele de jos din **Dongle settings** arată citirile reușite și cele eșuate.

## 9. Datele MQTT

La fiecare 10 secunde dongle-ul publică pe `tele/<topic>/SENSOR`, sub cheia `Growatt`:

```json
{"Growatt":{"Online":true,"Status":"PV charge","StatusCode":5,"PVPower":161,
 "PV1":{"Voltage":0,"Current":0,"Power":0},"PV2":{"Voltage":245.6,"Current":0.6,"Power":161},
 "Battery":{"SOC":21,"Voltage":51.9,"Power":-108.8,"DischargePower":0,"ChargeCurrent":7.3,"DischargeCurrent":0,"Current":7.3},
 "Output":{"Voltage":231.5,"Frequency":50.04,"Current":1.3,"Power":143,"ApparentPower":312,"Load":2.4},
 "Grid":{"Voltage":223.1,"Frequency":49.98,"Power":0,"ApparentPower":0,"ACChargePower":85,"ACChargeCurrent":0,"BypassPower":0},
 "Inverter":{"Temperature":24.8,"DCDCTemperature":21.8,"MPPT1Temperature":31.9,"MPPT2Temperature":30.8,"Current":1.9,
             "BusVoltage":455,"FanMPPT":0,"FanInverter":13,"FaultBits":0,"WarningBits":0,"FaultCode":0,"WarningCode":0},
 "Energy":{"PVToday":0.2,"PVTotal":502.3,"LoadToday":0.4,"LoadTotal":354.8,"ACChargeToday":0,
           "ACChargeTotal":4.1,"DischargeToday":0.3,"DischargeTotal":206.2,
           "ACDischargeToday":2.7,"ACDischargeTotal":183},
 "Settings":{"OutputPriority":"SBU","ChargerPriority":"Solar only","BatteryType":"Lithium","MaxChargeCurrent":48}}}
```

Unități: V, A, W, VA, Hz, °C, %, kWh. **Puterea bateriei e negativă la încărcare și pozitivă la descărcare**; `Battery.Current` e pozitiv la încărcare. `tele/<topic>/LWT` e `Online` / `Offline`. Intervalul e `TelePeriod` (implicit 10 s).

Încă două mesaje:

- `tele/<topic>/GROWATT_INFO`, o dată pe minut: seria, firmware-ul, ceasul invertorului, puterea nominală, intrarea de generator și **toate setările** în unități reale, cu aceleași nume ca în Solar Assistant:
  ```json
  {"Serial":"UYN6F3D017","Firmware":"100.06","ControlFirmware":"101.05","Clock":"2026-10-23 14:05:09",
   "RatedPower":6000,"Writable":false,"LastSet":null,
   "Settings":{"output_source_priority":"Solar/Battery/Utility","charger_source_priority":"Solar first",
               "max_charge_current":100,"back_to_battery_capacity":30,"battery_type":"Lithium BMS", "...": "..."}}
  ```
- `tele/<topic>/GROWATT_BMS`, la fiecare citire, doar de la invertorul legat la BMS-ul bateriei: SOC, SOH, tensiune, curent, temperatură, cicluri, tensiunea maximă / minimă pe celulă și diferența (mV), curentul și tensiunea de încărcare cerute de BMS, codurile de stare, eroare și avertizare.

### Schimbarea setărilor invertorului

Întâi bifezi **Allow inverter settings changes from Home Assistant** pe pagina de setări. Apoi trimiți pe `cmnd/<topic>/GrowattSet`:

```
output_source_priority Solar/Battery/Utility
max_charge_current 100
back_to_battery_capacity 30
```

Dongle-ul acceptă doar setările de mai jos, doar în limitele astea, și trimite o singură modificare odată. După scriere recitește registrul și raportează rezultatul pe `tele/<topic>/GROWATT_SET` (`"Result":"OK"` sau `"Error"` cu motivul).

| Setare | Registru | Valori |
| --- | --- | --- |
| `output_source_priority` | H1 | Solar/Battery/Utility · Solar first · Utility first · Solar/Utility/Battery |
| `charger_source_priority` | H2 | Solar first · Solar and utility simultaneously · Solar only |
| `energy_priority` | H116 | Battery/Load/Utility (BLU) · Load/Battery/Utility (LBU), firmware 100.08 sau mai nou |
| `ac_input_range` | H8 | Appliance · UPS · Generator |
| `max_charge_current` | H34 | 10–150 A |
| `max_grid_charge_current` / `max_generator_charge_current` | H38 / H83 | 0–80 A |
| `battery_absorption_charge_voltage` / `battery_float_charge_voltage` | H35 / H36 | 48,0–58,4 V (folosite la tipul de baterie User) |
| `to_grid_battery_capacity` / `back_to_battery_capacity` / `shutdown_battery_capacity` | H37 / H95 / H82 | 0–100 %, doar litiu |
| `grid_output_start_hour` / `grid_output_stop_hour` | H3 / H4 | 0–23 |
| `grid_charge_start_hour` / `grid_charge_stop_hour` | H5 / H6 | 0–23 |
| `buzzer` | H22 | Off · On |
| `overload_restart` / `overtemperature_restart` | H20 / H21 | cod brut 0–2 / 0–1 |

`cmnd/<topic>/GrowattClock` pune pe ceasul invertorului (H45–H50) ora dongle-ului, luată de pe internet (NTP). Cei șase regiștri se scriu dintr-o dată (FC16) și se citesc înapoi; dacă invertorul refuză sau păstrează altă oră, dongle-ul încearcă scrieri separate la 0,6 s una de alta, apoi încă o dată blocul, și raportează rezultatul în `sensor.growatt_N_last_setting_change`. Invertorul își resetează contoarele „azi” la miezul nopții lui, deci ceasul contează.

Pornirea / oprirea la distanță (H0), tensiunea și frecvența de ieșire (H18, H19) și tipul bateriei (H39) se văd, dar intenționat **nu** se pot scrie: o valoare greșită poate opri ieșirea, poate strica aparatele sau poate rupe legătura cu BMS-ul. Le schimbi din panoul invertorului. La invertoare în paralel, ține setările identice pe toate.

## 10. Home Assistant

### Senzorii

1. Instalezi add-on-ul **Mosquitto broker** și integrarea **MQTT**, apoi creezi un utilizator Home Assistant pentru dongle-uri.
2. Pe fiecare dongle, în **Dongle settings → MQTT**, treci adresa Home Assistant-ului, portul 1883 și acel utilizator. Notează **Topic**-ul fiecărui dongle.
3. Copiezi pachetul potrivit în `<config>/packages/`:
   - un invertor: [`homeassistant/packages/growatt_1_inverter.yaml`](../homeassistant/packages/growatt_1_inverter.yaml)
   - trei invertoare (de exemplu câte unul pe fază): [`homeassistant/packages/growatt_3_inverters.yaml`](../homeassistant/packages/growatt_3_inverters.yaml)
   - alt număr: `python tools/ha_package.py 2 > growatt_2_inverters.yaml`
4. În fișier înlocuiești `growatt_INV1`, `growatt_INV2`, ... cu topicurile dongle-urilor, în aceeași ordine ca invertoarele.
5. Activezi pachetele în `configuration.yaml` și repornești Home Assistant:
   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```
6. În **Settings → Devices & services → Helpers** setezi o singură dată **Growatt battery capacity** (kWh) și **Growatt battery minimum SOC** (%).

Fiecare invertor devine un dispozitiv „Growatt inverter N” cu aproximativ 60 de senzori numiți `sensor.growatt_N_...` (plus 14 senzori BMS pe invertorul 1; pentru alt invertor folosești `python tools/ha_package.py 3 2`) și, la **Configuration**, câte un select sau number pentru fiecare setare care se poate scrie (`select.growatt_N_output_source_priority`, `number.growatt_N_max_charge_current`, ...), plus butonul **Set inverter clock**. Ele schimbă invertorul doar după ce bifezi căsuța de pe pagina de setări a dongle-ului; `sensor.growatt_N_last_setting_change` arată rezultatul ultimei modificări. Integrarea GrowSolar are o pagină **Setări** care le folosește, cu **Aplică pe toate** pentru sistemele în paralel. Pachetul creează și senzorii de sumar folosiți de dashboard:

| Senzor | Ce înseamnă |
| --- | --- |
| `sensor.productie_solara_totala` | puterea PV a tuturor invertoarelor (W) |
| `sensor.consum_casa_total` | consumul casei, toate invertoarele (W) |
| `sensor.retea_putere_totala` | puterea luată din rețea, estimată din bypass și încărcarea din AC (W) |
| `sensor.baterie_putere_neta` | puterea bateriei, toate invertoarele, **pozitivă la încărcare** (W) |
| `sensor.baterie_soc_mediu` | SOC mediu (%) |
| `sensor.baterie_timp_pana_goala` / `_plina` | ore până la gol / plin, la puterea de acum |
| `sensor.baterie_eta_goala` / `_plina` | ora la care bateria va fi goală / plină |

Senzorii `*_energy_total` au statistici pe termen lung, deci merg în panoul **Energy** și în vederea pe lună a dashboard-ului.

Nu folosim un *blueprint* Home Assistant: blueprint-urile pentru template creează câte o entitate pentru fiecare folosire, iar maparea asta are nevoie de vreo 40 de entități pe invertor. Pachetul (și generatorul pentru alt număr de invertoare) face același lucru într-un singur fișier.

### Dashboard

<p><img src="img/dashboard-3.png" width="640" alt="Dashboard, trei invertoare">
<img src="img/dashboard-1-grid.png" width="640" alt="Dashboard, un invertor cu rețea">
<img src="img/dashboard-1.png" width="640" alt="Dashboard, un invertor off-grid"></p>

Trei pagini gata făcute, cu același design:

| Fișier | Pentru |
| --- | --- |
| [`homeassistant/dashboard/solar-3-inverters.html`](../homeassistant/dashboard/solar-3-inverters.html) | trei invertoare cu rețea (flux de energie cu rețea, card pentru fiecare invertor) |
| [`homeassistant/dashboard/solar-1-inverter-grid.html`](../homeassistant/dashboard/solar-1-inverter-grid.html) | un invertor cu rețea |
| [`homeassistant/dashboard/solar-1-inverter.html`](../homeassistant/dashboard/solar-1-inverter.html) | un invertor off-grid (fără rețea) |

1. Copiezi fișierul în `<config>/www/` (de exemplu cu add-on-ul File editor sau Samba).
2. **Settings → Dashboards → Add dashboard → New dashboard from scratch** și îi dai un nume.
3. Îl deschizi, **⋮ → Edit dashboard**, editezi vederea: **View type: Panel (single card)**.
4. Adaugi un card **Webpage** cu adresa `/local/solar-3-inverters.html` (sau `solar-1-inverter-grid.html`, `solar-1-inverter.html`).

Pagina citește senzorii direct din Home Assistant: fluxul de energie live, totalurile de azi, timpul până la baterie goală sau plină, câte un card pentru fiecare invertor și un grafic pe zi, 24 h, 48 h sau lună, cu economiile în RON. Setările sunt în blocul `CONFIG` de la începutul fișierului: titlu, număr de invertoare, cu rețea sau off-grid, prețul energiei. Plăcuțele cu prognoza solară folosesc integrarea **Forecast.Solar**; fără ea, arată „–”.

## 11. Modbus TCP

Dongle-ul ascultă pe portul **502**. Cererile sunt puse la rând și trimise invertorului pe rând, între citirile proprii ale dongle-ului, așa că îl pot folosi mai mulți clienți deodată (maxim 3 conexiuni).

- Unit ID 1 (sau 0/255) merge la adresa invertorului din pagina de setări.
- Funcțiile de citire 1–4 sunt mereu permise. Funcțiile de scriere 5, 6, 15, 16 sunt refuzate (excepția 01), dacă nu activezi scrierea.
- Dacă invertorul nu răspunde, clientul primește excepția 0B (gateway target failed to respond).

Exemplu pentru integrarea `modbus` din Home Assistant:

```yaml
modbus:
  - name: growatt
    type: tcp
    host: 192.168.1.50
    port: 502
    sensors:
      - name: Growatt SOC (Modbus)
        slave: 1
        address: 18
        input_type: input
        unit_of_measurement: "%"
```

Lista registrelor e în [registers.md](registers.md).

## 12. Actualizări

- **Firmware:** pagina principală → **Firmware Upgrade** → alegi `DongleGrowatt.bin` → **Start upgrade**. Setările rămân.
- **Doar scripturile:** **Tools → Manage File System** → încarci noul `growatt.be` → repornești. O actualizare de firmware nu înlocuiește scripturile deja aflate pe stick.

## 13. Depanare

| Simptom | Ce faci |
| --- | --- |
| esptool: „No serial data received” | inversezi TXD/RXD, verifici puntea IO9, scoți și bagi la loc adaptorul înainte de fiecare comandă |
| Pagina principală: „serial port error” | scriptul n-a putut deschide GPIO0/GPIO1; repornește; dacă rămâne, deschide un issue cu log-ul din consolă |
| Pagina principală: „no answer” | stick-ul nu e băgat complet, adresa Modbus e greșită, sau ai altă revizie de placă (alți pini UART) |
| MQTT „not connected” | folosește **Test server**; verifică utilizatorul și parola; la brokerii cu TLS bifează **Use TLS** și folosește portul 8883 |
| Clientul Modbus TCP dă timeout | invertorul răspunde mai greu când sunt multe cereri la rând; mărește timeout-ul clientului la 3 s |
| Ai uitat parola de admin | ștergi și rescrii cu adaptorul: `python -m esptool --chip esp32c3 -p COM7 --before no-reset erase-flash`, scoți și bagi la loc adaptorul, apoi pasul 5 |

## 14. Revenirea la firmware-ul Growatt

Legi adaptorul, pui puntea IO9, scoți și bagi la loc adaptorul, apoi:

```
python -m esptool --chip esp32c3 -p COM7 --before no-reset -b 230400 write-flash 0x0 Backup-ShineWiFi-X2\stock_backup_1.bin
```
