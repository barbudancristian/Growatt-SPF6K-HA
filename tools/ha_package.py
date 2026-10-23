#!/usr/bin/env python3
"""Generate a Home Assistant package for one or more DongleGrowatt inverters.

Creates, for each inverter n, MQTT sensors named sensor.growatt_<n>_<value>
(the names the dashboard in homeassistant/dashboard/ expects), plus the summary
helpers (total PV, house load, grid, battery net power, average SOC, time to
empty / full).

Usage:
    python tools/ha_package.py 3 [bms] > homeassistant/packages/growatt_3_inverters.yaml

[bms] is the inverter wired to the battery BMS (default 1, 0 = none); only that one
gets the BMS sensors.

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
    ("battery_charge_current", "Battery charge current", "Battery.ChargeCurrent", "A", "current", "measurement", 1, None),
    ("battery_current", "Battery current (+ charging)", "Battery.Current", "A", "current", "measurement", 1, None),
    ("grid_voltage", "Grid voltage", "Grid.Voltage", "V", "voltage", "measurement", 1, None),
    ("grid_frequency", "Grid frequency", "Grid.Frequency", "Hz", "frequency", "measurement", 2, None),
    ("ac_charge_power", "AC charge power", "Grid.ACChargePower", "W", "power", "measurement", 0, None),
    ("ac_charge_current", "AC charge current", "Grid.ACChargeCurrent", "A", "current", "measurement", 1, None),
    ("grid_power", "Grid power", None, "W", "power", "measurement", 0, "grid"),
    ("grid_apparent_power", "Grid apparent power", "Grid.ApparentPower", "VA", "apparent_power", "measurement", 0, None),
    ("bypass_power", "Grid to load power", "Grid.BypassPower", "W", "power", "measurement", 0, None),
    ("inverter_temperature", "Inverter temperature", "Inverter.Temperature", "°C", "temperature", "measurement", 1, None),
    ("dcdc_temperature", "DC-DC temperature", "Inverter.DCDCTemperature", "°C", "temperature", "measurement", 1, None),
    ("bus_voltage", "Bus voltage", "Inverter.BusVoltage", "V", "voltage", "measurement", 1, None),
    ("mppt1_temperature", "MPPT 1 temperature", "Inverter.MPPT1Temperature", "°C", "temperature", "measurement", 1, None),
    ("mppt2_temperature", "MPPT 2 temperature", "Inverter.MPPT2Temperature", "°C", "temperature", "measurement", 1, None),
    ("inverter_current", "Inverter current", "Inverter.Current", "A", "current", "measurement", 1, None),
    ("fan_mppt", "MPPT fan", "Inverter.FanMPPT", "%", None, "measurement", 0, None),
    ("fan_inverter", "Inverter fan", "Inverter.FanInverter", "%", None, "measurement", 0, None),
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
]


# tele/<topic>/GROWATT_INFO (every minute): (key, name, json path, unit, device_class, icon)
INFO = [
    ("serial_number", "Serial number", "Serial", None, None, "mdi:identifier"),
    ("firmware", "Firmware", "Firmware", None, None, "mdi:chip"),
    ("control_firmware", "Control firmware", "ControlFirmware", None, None, "mdi:chip"),
    ("inverter_clock", "Inverter clock", "Clock", None, None, "mdi:clock-outline"),
    ("rated_power", "Rated power", "RatedPower", "W", "power", None),
    ("generator_power", "Generator power", "Generator.Power", "W", "power", None),
    ("generator_voltage", "Generator voltage", "Generator.Voltage", "V", "voltage", None),
    ("setting_remote_switch", "Remote switch", "Settings.remote_switch", None, None, "mdi:power"),
    ("setting_output_voltage", "Output voltage setting", "Settings.output_voltage", None, None, "mdi:sine-wave"),
    ("setting_output_frequency", "Output frequency setting", "Settings.output_frequency", None, None, "mdi:sine-wave"),
    ("last_setting_change", "Last setting change", "LastSet.Message", None, None, "mdi:history"),
]

# tele/<topic>/GROWATT_BMS (only the inverter wired to the BMS)
BMS = [
    ("bms_soc", "BMS SOC", "SOC", "%", "battery", "measurement", 0),
    ("bms_soh", "BMS state of health", "SOH", "%", None, "measurement", 0),
    ("bms_voltage", "BMS voltage", "Voltage", "V", "voltage", "measurement", 2),
    ("bms_current", "BMS current", "Current", "A", "current", "measurement", 1),
    ("bms_temperature", "BMS temperature", "Temperature", "°C", "temperature", "measurement", 1),
    ("bms_cycles", "BMS cycles", "Cycles", None, None, "total_increasing", 0),
    ("bms_cell_max", "Highest cell voltage", "CellMax", "V", "voltage", "measurement", 3),
    ("bms_cell_min", "Lowest cell voltage", "CellMin", "V", "voltage", "measurement", 3),
    ("bms_cell_delta", "Cell voltage difference", "CellDelta", "V", "voltage", "measurement", 3),  # dongle sends mV
    ("bms_max_charge_current", "BMS max charge current", "MaxChargeCurrent", "A", "current", "measurement", 1),
    ("bms_charge_voltage", "BMS charge voltage", "ChargeVoltage", "V", "voltage", "measurement", 2),
    ("bms_status", "BMS status code", "Status", None, None, None, None),
    ("bms_error", "BMS error code", "Error", None, None, None, None),
    ("bms_warning", "BMS warning code", "Warning", None, None, None, None),
]

# Settings the dongle can change (same names and options as in dongle/growatt.be GW_SETTINGS)
SELECTS = [
    ("output_source_priority", "Output source priority", ["Solar/Battery/Utility", "Solar first", "Utility first", "Solar/Utility/Battery"]),
    ("charger_source_priority", "Charger source priority", ["Solar first", "Solar and utility simultaneously", "Solar only"]),
    ("energy_priority", "Energy priority (BLU/LBU)", ["Battery/Load/Utility", "Load/Battery/Utility"]),
    ("ac_input_range", "AC input range", ["Appliance", "UPS", "Generator"]),
    ("buzzer", "Buzzer", ["Off", "On"]),
]
# (key, name, min, max, step, unit, device_class)
NUMBERS = [
    ("max_charge_current", "Max charge current", 10, 150, 1, "A", "current"),
    ("max_grid_charge_current", "Max grid charge current", 0, 80, 1, "A", "current"),
    ("max_generator_charge_current", "Max generator charge current", 0, 80, 1, "A", "current"),
    ("battery_absorption_charge_voltage", "Absorption (bulk) charge voltage", 48, 58.4, 0.1, "V", "voltage"),
    ("battery_float_charge_voltage", "Float charge voltage", 48, 58.4, 0.1, "V", "voltage"),
    ("to_grid_battery_capacity", "Switch to grid at SOC", 0, 100, 1, "%", None),
    ("back_to_battery_capacity", "Back to battery at SOC", 0, 100, 1, "%", None),
    ("shutdown_battery_capacity", "Battery cut-off at SOC", 0, 100, 1, "%", None),
    ("grid_output_start_hour", "Grid output start hour", 0, 23, 1, "h", None),
    ("grid_output_stop_hour", "Grid output stop hour", 0, 23, 1, "h", None),
    ("grid_charge_start_hour", "Grid charge start hour", 0, 23, 1, "h", None),
    ("grid_charge_stop_hour", "Grid charge stop hour", 0, 23, 1, "h", None),
    ("overload_restart", "Overload restart (code)", 0, 2, 1, None, None),
    ("overtemperature_restart", "Over-temperature restart (code)", 0, 1, 1, None, None),
]


def getter(path):
    parts = path.split(".")
    expr = "value_json.get('Growatt', {})"
    for p in parts[:-1]:
        expr += f".get('{p}', {{}})"
    return expr + f".get('{parts[-1]}')"


def rnd(expr, prec):
    """Round a number to the sensor's precision (the dongle sends 32-bit floats such as 53.080006)."""
    if prec is None:
        return expr
    if prec == 0:
        return "(" + expr + ") | round(0) | int"
    return "(" + expr + ") | round(" + str(prec) + ")"


def template(path, special, prec=None):
    if special == "negate":
        return "{% set v = " + getter(path) + " %}{{ " + rnd("-v", prec) + " if v is number else none }}"
    if special == "grid":
        # input 36-37 on firmware that has it, otherwise grid to load in bypass plus grid charging
        return ("{% set g = value_json.get('Growatt', {}) %}"
                "{% set gp = g.get('Grid', {}).get('Power') %}"
                "{% if gp is number and gp > 0 %}{{ gp | round(0) | int }}{% else %}"
                "{% set out = g.get('Output', {}).get('Power') %}"
                "{% set ac = g.get('Grid', {}).get('ACChargePower') %}"
                "{% if out is number and ac is number %}"
                "{{ ((out if g.get('StatusCode') in [8, 9, 10, 11] else 0) + ac) | round(0) | int }}"
                "{% else %}{{ none }}{% endif %}{% endif %}")
    if prec is None:
        return "{{ " + getter(path) + " }}"
    return "{% set v = " + getter(path) + " %}{{ " + rnd("v", prec) + " if v is number else none }}"


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
            f"      value_template: {q(template(path, special, prec))}",
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


def device(n):
    return [
        "      device:",
        f"        identifiers: [\"growatt_inverter_{n}\"]",
        f"        name: \"Growatt inverter {n}\"",
        "        manufacturer: \"Growatt\"",
        "        model: \"SPF (DongleGrowatt)\"",
    ]


def lwt(topic):
    return [
        "      availability:",
        f"        - topic: \"tele/{topic}/LWT\"",
        "          payload_available: \"Online\"",
        "          payload_not_available: \"Offline\"",
    ]


def jget(root, path):
    expr = "value_json"
    parts = path.split(".")
    for p in parts[:-1]:
        expr += f".get('{p}', {{}})"
    return expr + f".get('{parts[-1]}')"


def info_sensors(n):
    topic = f"growatt_INV{n}"
    out = []
    for key, name, path, unit, dc, icon in INFO:
        lines = [
            f"    - name: {q(name)}",
            f"      unique_id: growatt_{n}_{key}",
            f"      default_entity_id: sensor.growatt_{n}_{key}",
            f"      state_topic: \"tele/{topic}/GROWATT_INFO\"",
            f"      value_template: {q('{{ ' + jget('', path) + ' }}')}",
            "      entity_category: diagnostic",
        ] + lwt(topic)
        if unit:
            lines.append(f"      unit_of_measurement: {q(unit)}")
        if dc:
            lines.append(f"      device_class: {dc}")
        if icon:
            lines.append(f"      icon: {icon}")
        out.append("\n".join(lines + device(n)))
    return out


def bms_sensors(n):
    topic = f"growatt_INV{n}"
    out = []
    for key, name, path, unit, dc, sc, prec in BMS:
        tmpl = "{% set v = " + jget("", path) + " %}{{ " + rnd("v", prec) + " if v is number else none }}"
        if path == "CellDelta":
            tmpl = "{% set v = " + jget("", path) + " %}{{ " + rnd("v / 1000", prec) + " if v is number else none }}"
        lines = [
            f"    - name: {q(name)}",
            f"      unique_id: growatt_{n}_{key}",
            f"      default_entity_id: sensor.growatt_{n}_{key}",
            f"      state_topic: \"tele/{topic}/GROWATT_BMS\"",
            f"      value_template: {q(tmpl)}",
            "      expire_after: 120",
        ] + lwt(topic)
        if unit:
            lines.append(f"      unit_of_measurement: {q(unit)}")
        if dc:
            lines.append(f"      device_class: {dc}")
        if sc:
            lines.append(f"      state_class: {sc}")
        if prec is not None:
            lines.append(f"      suggested_display_precision: {prec}")
        out.append("\n".join(lines + device(n)))
    return out


def settings_entities(n):
    """select / number entities that send GrowattSet <name> <value> to the dongle."""
    topic = f"growatt_INV{n}"
    sel, num = [], []
    for key, name, options in SELECTS:
        lines = [
            f"    - name: {q(name)}",
            f"      unique_id: growatt_{n}_{key}",
            f"      default_entity_id: select.growatt_{n}_{key}",
            f"      state_topic: \"tele/{topic}/GROWATT_INFO\"",
            f"      value_template: {q('{{ value_json.Settings.' + key + ' }}')}",
            f"      command_topic: \"cmnd/{topic}/GrowattSet\"",
            f"      command_template: {q(key + ' {{ value }}')}",
            "      options:",
        ] + [f"        - {q(o)}" for o in options] + ["      entity_category: config"] + lwt(topic)
        sel.append("\n".join(lines + device(n)))
    for key, name, mn, mx, step, unit, dc in NUMBERS:
        lines = [
            f"    - name: {q(name)}",
            f"      unique_id: growatt_{n}_{key}",
            f"      default_entity_id: number.growatt_{n}_{key}",
            f"      state_topic: \"tele/{topic}/GROWATT_INFO\"",
            f"      value_template: {q('{{ value_json.Settings.' + key + ' }}')}",
            f"      command_topic: \"cmnd/{topic}/GrowattSet\"",
            f"      command_template: {q(key + ' {{ value }}')}",
            f"      min: {mn}",
            f"      max: {mx}",
            f"      step: {step}",
            "      mode: box",
            "      entity_category: config",
        ] + lwt(topic)
        if unit:
            lines.append(f"      unit_of_measurement: {q(unit)}")
        if dc:
            lines.append(f"      device_class: {dc}")
        num.append("\n".join(lines + device(n)))
    btn = "\n".join([
        "    - name: \"Set inverter clock\"",
        f"      unique_id: growatt_{n}_sync_clock",
        f"      default_entity_id: button.growatt_{n}_sync_clock",
        f"      command_topic: \"cmnd/{topic}/GrowattClock\"",
        "      icon: mdi:clock-check-outline",
        "      entity_category: config",
    ] + lwt(topic) + device(n))
    return sel, num, [btn]


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
    # inverter wired to the BMS (its dongle publishes GROWATT_BMS); 0 = none
    bms = int(sys.argv[2]) if len(sys.argv) > 2 else 1
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
#
# Settings: select.growatt_<n>_* / number.growatt_<n>_* change the inverter through the
# dongle (command GrowattSet). They only work after ticking "Allow inverter settings
# changes from Home Assistant" on the dongle's settings page; otherwise the dongle refuses
# and sensor.growatt_<n>_last_setting_change shows why.

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
        blocks += mqtt_sensors(i) + info_sensors(i)
        if i == bms:
            blocks += bms_sensors(i)
    print("\n".join(blocks))
    sel, num, btn = [], [], []
    for i in range(1, n + 1):
        a, b, c = settings_entities(i)
        sel += a
        num += b
        btn += c
    print("  select:")
    print("\n".join(sel))
    print("  number:")
    print("\n".join(num))
    print("  button:")
    print("\n".join(btn))
    print("""
template:
  - sensor:""")
    print("\n".join(helpers(n)))


if __name__ == "__main__":
    main()
