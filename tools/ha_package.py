#!/usr/bin/env python3
"""Generate a Home Assistant package for one or more DongleGrowatt inverters.

Creates, for each inverter n, MQTT sensors named sensor.growatt_<n>_<value>
(the names the dashboard in homeassistant/dashboard/ expects), plus the summary
helpers (total PV, house load, grid, battery net power, average SOC, time to
empty / full).

Usage:
    python tools/ha_package.py 3 > homeassistant/packages/growatt_3_inverters.yaml

SPDX-License-Identifier: GPL-3.0-or-later
"""
import sys

# (key, name, json path, unit, device_class, state_class, precision, special)
VALUES = [
    ("status", "Status code", "StatusCode", None, None, None, None, None),
    ("status_text", "Status", "Status", None, None, None, None, None),
    ("output_power", "Output power", "Output.Power", "W", "power", "measurement", 0, None),
    ("output_apparent_power", "Output apparent power", "Output.ApparentPower", "VA", "apparent_power", "measurement", 0, None),
    ("load_percentage", "Load percentage", "Output.Load", "%", None, "measurement", 1, None),
    ("output_voltage", "Output voltage", "Output.Voltage", "V", "voltage", "measurement", 1, None),
    ("output_frequency", "Output frequency", "Output.Frequency", "Hz", "frequency", "measurement", 2, None),
    ("output_current", "Output current", "Output.Current", "A", "current", "measurement", 1, None),
    ("pv1_power", "PV1 power", "PV1.Power", "W", "power", "measurement", 0, None),
    ("pv1_voltage", "PV1 voltage", "PV1.Voltage", "V", "voltage", "measurement", 1, None),
    ("pv1_current", "PV1 current", "PV1.Current", "A", "current", "measurement", 1, None),
    ("pv2_power", "PV2 power", "PV2.Power", "W", "power", "measurement", 0, None),
    ("pv2_voltage", "PV2 voltage", "PV2.Voltage", "V", "voltage", "measurement", 1, None),
    ("pv2_current", "PV2 current", "PV2.Current", "A", "current", "measurement", 1, None),
    ("battery_power", "Battery power (+ charging)", "Battery.Power", "W", "power", "measurement", 0, "negate"),
    ("battery_voltage", "Battery voltage", "Battery.Voltage", "V", "voltage", "measurement", 2, None),
    ("battery_soc", "Battery SOC", "Battery.SOC", "%", "battery", "measurement", 0, None),
    ("battery_discharge_current", "Battery discharge current", "Battery.DischargeCurrent", "A", "current", "measurement", 1, None),
    ("grid_voltage", "Grid voltage", "Grid.Voltage", "V", "voltage", "measurement", 1, None),
    ("grid_frequency", "Grid frequency", "Grid.Frequency", "Hz", "frequency", "measurement", 2, None),
    ("ac_charge_power", "AC charge power", "Grid.ACChargePower", "W", "power", "measurement", 0, None),
    ("grid_power", "Grid power (estimate)", None, "W", "power", "measurement", 0, "grid"),
    ("inverter_temperature", "Inverter temperature", "Inverter.Temperature", "°C", "temperature", "measurement", 1, None),
    ("dcdc_temperature", "DC-DC temperature", "Inverter.DCDCTemperature", "°C", "temperature", "measurement", 1, None),
    ("bus_voltage", "Bus voltage", "Inverter.BusVoltage", "V", "voltage", "measurement", 1, None),
    ("fault_bit", "Fault code", "Inverter.FaultCode", None, None, None, None, None),
    ("warning_bit", "Warning code", "Inverter.WarningCode", None, None, None, None, None),
    ("pv_energy_today", "PV energy today", "Energy.PVToday", "kWh", "energy", "total_increasing", 1, None),
    ("pv_energy_total", "PV energy total", "Energy.PVTotal", "kWh", "energy", "total_increasing", 1, None),
    ("op_discharge_energy_today", "Load energy today", "Energy.LoadToday", "kWh", "energy", "total_increasing", 1, None),
    ("op_discharge_energy_total", "Load energy total", "Energy.LoadTotal", "kWh", "energy", "total_increasing", 1, None),
    ("battery_discharge_energy_today", "Battery discharge today", "Energy.DischargeToday", "kWh", "energy", "total_increasing", 1, None),
    ("battery_discharge_energy_total", "Battery discharge total", "Energy.DischargeTotal", "kWh", "energy", "total_increasing", 1, None),
    ("ac_charge_energy_today", "AC charge today", "Energy.ACChargeToday", "kWh", "energy", "total_increasing", 1, None),
    ("ac_charge_energy_total", "AC charge total", "Energy.ACChargeTotal", "kWh", "energy", "total_increasing", 1, None),
    ("ac_discharge_energy_today", "Grid to load today", "Energy.ACDischargeToday", "kWh", "energy", "total_increasing", 1, None),
    ("ac_discharge_energy_total", "Grid to load total", "Energy.ACDischargeTotal", "kWh", "energy", "total_increasing", 1, None),
    ("output_priority", "Output priority", "Settings.OutputPriority", None, None, None, None, None),
    ("charger_priority", "Charger priority", "Settings.ChargerPriority", None, None, None, None, None),
    ("battery_type", "Battery type", "Settings.BatteryType", None, None, None, None, None),
    ("max_charge_current", "Max charge current", "Settings.MaxChargeCurrent", "A", "current", None, 0, None),
]


def getter(path):
    parts = path.split(".")
    expr = "value_json.get('Growatt', {})"
    for p in parts[:-1]:
        expr += f".get('{p}', {{}})"
    return expr + f".get('{parts[-1]}')"


def template(path, special):
    if special == "negate":
        return "{% set v = " + getter(path) + " %}{{ -v if v is number else none }}"
    if special == "grid":
        return ("{% set g = value_json.get('Growatt', {}) %}"
                "{% set out = g.get('Output', {}).get('Power') %}"
                "{% set ac = g.get('Grid', {}).get('ACChargePower') %}"
                "{% if out is number and ac is number %}"
                "{{ (out if g.get('StatusCode') in [8, 9, 10, 11] else 0) + ac }}"
                "{% else %}{{ none }}{% endif %}")
    return "{{ " + getter(path) + " }}"


def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def mqtt_sensors(n):
    topic = f"growatt_INV{n}"
    out = []
    for key, name, path, unit, dc, sc, prec, special in VALUES:
        lines = [
            f"    - name: {q(name)}",
            f"      unique_id: growatt_{n}_{key}",
            f"      default_entity_id: sensor.growatt_{n}_{key}",
            f"      state_topic: \"tele/{topic}/SENSOR\"",
            f"      value_template: {q(template(path, special))}",
            "      availability_mode: all",
            "      availability:",
            f"        - topic: \"tele/{topic}/LWT\"",
            "          payload_available: \"Online\"",
            "          payload_not_available: \"Offline\"",
            f"        - topic: \"tele/{topic}/SENSOR\"",
            "          value_template: \"{{ 'Online' if value_json.get('Growatt', {}).get('Online') else 'Offline' }}\"",
            "          payload_available: \"Online\"",
            "          payload_not_available: \"Offline\"",
        ]
        if unit:
            lines.append(f"      unit_of_measurement: {q(unit)}")
        if dc:
            lines.append(f"      device_class: {dc}")
        if sc:
            lines.append(f"      state_class: {sc}")
        if prec is not None:
            lines.append(f"      suggested_display_precision: {prec}")
        lines += [
            "      device:",
            f"        identifiers: [\"growatt_inverter_{n}\"]",
            f"        name: \"Growatt inverter {n}\"",
            "        manufacturer: \"Growatt\"",
            "        model: \"SPF (DongleGrowatt)\"",
        ]
        out.append("\n".join(lines))
    return out


def ids(n, key):
    return "[" + ", ".join(f"'sensor.growatt_{i}_{key}'" for i in range(1, n + 1)) + "]"


def helpers(n):
    def total(keys):
        lst = "[" + ", ".join(f"'sensor.growatt_{i}_{k}'" for i in range(1, n + 1) for k in keys) + "]"
        return ("{% set l = " + lst + " | select('has_value') | list %}"
                "{{ (l | map('states') | map('float', 0) | sum) | round(0) if l | count > 0 else none }}")
    soc = ("{% set l = " + ids(n, "battery_soc") + " | select('has_value') | map('states') | map('float') | list %}"
           "{{ (l | sum / l | count) | round(0) if l | count > 0 else none }}")
    h_empty = ("{% set p = states('sensor.baterie_putere_neta') | float(0) %}"
               "{% set s = states('sensor.baterie_soc_mediu') | float(none) %}"
               "{% set cap = states('input_number.growatt_battery_capacity') | float(10) %}"
               "{% set mn = states('input_number.growatt_battery_min_soc') | float(15) %}"
               "{% if p < -10 and s is number %}{{ ([s - mn, 0] | max / 100 * cap * 1000 / -p) | round(2) }}{% else %}{{ none }}{% endif %}")
    h_full = ("{% set p = states('sensor.baterie_putere_neta') | float(0) %}"
              "{% set s = states('sensor.baterie_soc_mediu') | float(none) %}"
              "{% set cap = states('input_number.growatt_battery_capacity') | float(10) %}"
              "{% if p > 10 and s is number %}{{ ([100 - s, 0] | max / 100 * cap * 1000 / p) | round(2) }}{% else %}{{ none }}{% endif %}")
    eta = lambda src: ("{% set h = states('" + src + "') | float(none) %}"
                       "{{ (now() + timedelta(hours=h)).isoformat() if h is number else none }}")
    items = [
        ("Producție solară totală", "productie_solara_totala", total(["pv1_power", "pv2_power"]), "W", "power", "measurement"),
        ("Consum casă total", "consum_casa_total", total(["output_power"]), "W", "power", "measurement"),
        ("Rețea putere totală", "retea_putere_totala", total(["grid_power"]), "W", "power", "measurement"),
        ("Baterie putere netă", "baterie_putere_neta", total(["battery_power"]), "W", "power", "measurement"),
        ("Baterie SOC mediu", "baterie_soc_mediu", soc, "%", "battery", "measurement"),
        ("Baterie timp până la gol", "baterie_timp_pana_goala", h_empty, "h", "duration", None),
        ("Baterie timp până la plin", "baterie_timp_pana_plina", h_full, "h", "duration", None),
        ("Baterie ETA gol", "baterie_eta_goala", eta("sensor.baterie_timp_pana_goala"), None, "timestamp", None),
        ("Baterie ETA plin", "baterie_eta_plina", eta("sensor.baterie_timp_pana_plina"), None, "timestamp", None),
    ]
    out = []
    for name, oid, tmpl, unit, dc, sc in items:
        lines = [
            f"      - name: {q(name)}",
            f"        unique_id: growatt_helper_{oid}",
            f"        default_entity_id: sensor.{oid}",
            f"        state: {q(tmpl)}",
        ]
        if unit:
            lines.append(f"        unit_of_measurement: {q(unit)}")
        if dc:
            lines.append(f"        device_class: {dc}")
        if sc:
            lines.append(f"        state_class: {sc}")
        out.append("\n".join(lines))
    return out


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    plural = "inverter" if n == 1 else "inverters"
    topics = "\n".join(f"#   growatt_INV{i}  ->  MQTT topic of the dongle in inverter {i}" for i in range(1, n + 1))
    print(f"""# DongleGrowatt - Home Assistant package for {n} Growatt SPF {plural}
# Generated by tools/ha_package.py {n}
#
# 1. Replace every placeholder below with the MQTT topic of each dongle
#    (shown on the dongle's "Dongle settings" page, field "Topic"):
{topics}
# 2. Copy this file to <config>/packages/ and enable packages in configuration.yaml:
#      homeassistant:
#        packages: !include_dir_named packages
# 3. Restart Home Assistant, then set the battery capacity (kWh) and minimum SOC (%) once
#    in Settings > Devices & services > Helpers > "Growatt battery ...". They are kept after restarts.
#
# Entities: sensor.growatt_<n>_<value> for each inverter, plus the summary sensors used by
# the dashboard (sensor.productie_solara_totala, sensor.consum_casa_total, ...).
# Battery power here is positive while CHARGING (the dashboard expects that).

input_number:
  growatt_battery_capacity:
    name: Growatt battery capacity
    min: 1
    max: 100
    step: 0.1
    unit_of_measurement: kWh
    mode: box
  growatt_battery_min_soc:
    name: Growatt battery minimum SOC
    min: 0
    max: 50
    step: 1
    unit_of_measurement: "%"
    mode: box

mqtt:
  sensor:""")
    blocks = []
    for i in range(1, n + 1):
        blocks += mqtt_sensors(i)
    print("\n".join(blocks))
    print("""
template:
  - sensor:""")
    print("\n".join(helpers(n)))


if __name__ == "__main__":
    main()
