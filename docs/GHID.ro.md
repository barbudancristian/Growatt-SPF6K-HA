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

Fă backup la toată memoria de două ori și compară:

```
python -m esptool --chip esp32c3 -p COM7 --before no-reset -b 230400 read-flash 0 ALL stock_backup_1.bin
python -m esptool --chip esp32c3 -p COM7 --before no-reset -b 230400 read-flash 0 ALL stock_backup_2.bin
Get-FileHash stock_backup_1.bin, stock_backup_2.bin
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
| Inverter / Modbus | adresa Modbus a invertorului (1), intervalul de citire (10 s), portul Modbus TCP (502, 0 = oprit) și dacă clienții TCP au voie să **scrie** setări (implicit nu). |

Câmpurile de parolă lăsate goale păstrează parola actuală. Rețeaua Wi-Fi propriu-zisă se schimbă din **Configuration → Wi-Fi**.

## 8. Montarea în invertor

Bagi stick-ul în portul de dongle al invertorului. În câteva secunde pagina principală arată invertorul: stare, SOC și puterea bateriei, PV, consum, ieșirea AC, temperatura, energia de azi și setările invertorului.

„no answer” înseamnă că invertorul nu răspunde: verifică dacă stick-ul e băgat complet și dacă adresa Modbus e 1. Contoarele de jos din **Dongle settings** arată citirile reușite și cele eșuate.

## 9. Datele MQTT

La fiecare 10 secunde dongle-ul publică pe `tele/<topic>/SENSOR`, sub cheia `Growatt`:

```json
{"Growatt":{"Online":true,"Status":"PV charge","StatusCode":5,"PVPower":161,
 "PV1":{"Voltage":0,"Current":0,"Power":0},"PV2":{"Voltage":245.6,"Current":0.6,"Power":161},
 "Battery":{"SOC":21,"Voltage":51.9,"Power":-108.8,"DischargeCurrent":0},
 "Output":{"Voltage":231.5,"Frequency":50.04,"Current":1.3,"Power":143,"ApparentPower":312,"Load":2.4},
 "Inverter":{"Temperature":24.8,"DCDCTemperature":21.8,"BusVoltage":455,"FaultCode":0,"WarningCode":0},
 "Energy":{"PVToday":0.2,"PVTotal":502.3,"LoadToday":0.4,"LoadTotal":354.8,"ACChargeToday":0,
           "ACChargeTotal":4.1,"DischargeToday":0.3,"DischargeTotal":206.2},
 "Settings":{"OutputPriority":"SBU","ChargerPriority":"Solar only","BatteryType":"Lithium","MaxChargeCurrent":48}}}
```

Unități: V, A, W, VA, Hz, °C, %, kWh. **Puterea bateriei e negativă la încărcare și pozitivă la descărcare.** `tele/<topic>/LWT` e `Online` / `Offline`. Intervalul e `TelePeriod` (implicit 10 s).

## 10. Home Assistant

1. Instalezi add-on-ul **Mosquitto broker** și integrarea **MQTT**, apoi creezi un utilizator Home Assistant pentru dongle.
2. În **Dongle settings → MQTT** treci adresa Home Assistant-ului, portul 1883 și acel utilizator.
3. Copiezi [`homeassistant/donglegrowatt.yaml`](../homeassistant/donglegrowatt.yaml) în `<config>/packages/`, înlocuiești `growatt_ABC123` cu topicul dongle-ului tău, activezi pachetele în `configuration.yaml` și repornești Home Assistant.

Primești un dispozitiv „Growatt inverter” cu 35 de senzori, gata pentru panoul Energy.

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
python -m esptool --chip esp32c3 -p COM7 --before no-reset -b 230400 write-flash 0x0 stock_backup_1.bin
```
