/*
  DongleGrowatt - build settings for the Growatt ShineWiFi-X2 (ESP32-C3)

  Copied into the firmware source tree as tasmota/user_config_override.h by the
  GitHub workflow in .github/workflows/build.yml.

  SPDX-License-Identifier: GPL-3.0-or-later
*/
#ifndef _USER_CONFIG_OVERRIDE_H_
#define _USER_CONFIG_OVERRIDE_H_

// ---- Name shown on the hotspot, in the web pages and in MQTT ----
#undef  PROJECT
#define PROJECT                "DongleGrowatt"
#undef  FRIENDLY_NAME
#define FRIENDLY_NAME          "DongleGrowatt"
// Hotspot / host name: "DongleGrowatt-1234" (the %.0s swallows the MQTT topic argument)
#undef  WIFI_DEFAULT_HOSTNAME
#define WIFI_DEFAULT_HOSTNAME  "DongleGrowatt%.0s-%04d"
// MQTT topic: "growatt_ABC123" (last 6 hex digits of the MAC)
#undef  MQTT_TOPIC
#define MQTT_TOPIC             "growatt_%06X"
// Password of the setup hotspot (at least 8 characters)
#undef  WIFI_AP_PASSPHRASE
#define WIFI_AP_PASSPHRASE     "donglegrowatt"

// ---- Telemetry every 10 s (tele/<topic>/SENSOR, key "Growatt") ----
#undef  TELE_PERIOD
#define TELE_PERIOD            10

// ---- Bigger MQTT messages: the SENSOR message with all inverter values is about 1.1 kB ----
#undef  MQTT_MAX_PACKET_SIZE
#define MQTT_MAX_PACKET_SIZE   2048

// ---- No automatic online updates from a third-party server ----
#undef  OTA_URL
#define OTA_URL                ""

// ---- No automatic announcement on tasmota/discovery/... ----
// The Home Assistant packages in homeassistant/packages/ read the data directly,
// so the announcement is not needed and would only show a "Discovered" card in HA.
#undef  USE_TASMOTA_DISCOVERY

// ---- Time zone: Romania / Eastern Europe (EET, UTC+2; summer EEST, UTC+3) ----
// Change it on the device with the Timezone / TimeStd / TimeDst commands if needed.
#undef  APP_TIMEZONE
#define APP_TIMEZONE           99
#undef  TIME_DST_HOUR
#define TIME_DST_HOUR          3
#undef  TIME_DST_OFFSET
#define TIME_DST_OFFSET        +180
#undef  TIME_STD_HOUR
#define TIME_STD_HOUR          4
#undef  TIME_STD_OFFSET
#define TIME_STD_OFFSET        +120

#endif  // _USER_CONFIG_OVERRIDE_H_
