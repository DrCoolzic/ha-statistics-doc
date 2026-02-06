# Real-world examples of statistics from non-sensor domains

This document provides real-world examples of how statistics can be generated from non-sensor domains in Home Assistant.

## 1. **Number Domain** (Most Common Non-Sensor)

The `number` domain is frequently used for configuration values that you want to track over time:

```yaml
number:
  - platform: template
    name: "Target Temperature"
    min: 15
    max: 30
    step: 0.5
    unit_of_measurement: "°C"
    state_class: measurement  # ✅ Generates statistics
```

**Use case**: Track how you adjust your thermostat target temperature over time

## 2. **Input Number** (Helper Entity)

Input numbers created through the UI can have statistics:

```yaml
input_number:
  daily_budget:
    name: Daily Energy Budget
    min: 0
    max: 100
    step: 1
    unit_of_measurement: "kWh"
    mode: box
    # Add state_class via customize:
```

Then customize it:

```yaml
homeassistant:
  customize:
    input_number.daily_budget:
      state_class: measurement
```

**Use case**: Track your energy budget settings over time

## 3. **Climate Domain** (Indirectly)

While climate entities themselves don't generate statistics, their **attributes** can be exposed as separate entities with statistics:

```yaml
template:
  - sensor:
      - name: "Thermostat Current Temperature"
        unit_of_measurement: "°C"
        state_class: measurement
        state: "{{ state_attr('climate.living_room', 'current_temperature') }}"
```

But if you create a template **number** or **sensor** from climate attributes, those can have statistics.

## 4. **Binary Sensor** (Duration Tracking)

Binary sensors can track duration using `total_increasing`:

```yaml
template:
  - sensor:
      - name: "Door Open Duration Today"
        unit_of_measurement: "s"
        state_class: total_increasing
        device_class: duration
        state: >
          {% if is_state('binary_sensor.front_door', 'on') %}
            {{ (now() - states.binary_sensor.front_door.last_changed).total_seconds() }}
          {% else %}
            0
          {% endif %}
```

**Use case**: Track cumulative time door was open

## 5. **Counter Helper** (With Custom State Class)

Counter helpers can be configured to generate statistics:

```yaml
counter:
  guests_today:
    name: Guests Count Today
    icon: mdi:account-multiple
    # Then customize to add statistics tracking
```

Customize:

```yaml
homeassistant:
  customize:
    counter.guests_today:
      state_class: total
      unit_of_measurement: "visitors"
```

## 6. **Template Entities** (Any Domain)

You can create template entities in various domains with statistics:

### Template Number with Statistics

```yaml
template:
  - number:
      - name: "Calculated Power Factor"
        state: >
          {% set voltage = states('sensor.voltage') | float %}
          {% set current = states('sensor.current') | float %}
          {{ (voltage * current / 1000) | round(2) }}
        unit_of_measurement: "kW"
        state_class: measurement
```

### Template Binary Sensor (State Duration)

```yaml
template:
  - sensor:
      - name: "Motion Active Time"
        state: >
          {{ (now() - states.binary_sensor.motion.last_changed).total_seconds() 
             if is_state('binary_sensor.motion', 'on') else 0 }}
        unit_of_measurement: "s"
        state_class: measurement
        device_class: duration
```

## 7. **Utility Meter** (Uses Input Sensor)

While utility meters themselves are sensors, they can be fed from non-sensor entities:

```yaml
utility_meter:
  daily_door_openings:
    source: counter.door_opened_count  # ← Counter, not sensor!
    cycle: daily
```

## 8. **MQTT Number** (External Devices)

MQTT number entities with statistics:

```yaml
mqtt:
  - number:
      name: "Smart Plug Power Limit"
      command_topic: "home/plug1/power_limit/set"
      state_topic: "home/plug1/power_limit"
      unit_of_measurement: "W"
      state_class: measurement
```

## Real-World Example: Tracking Manual Adjustments

Here's a practical example using `input_number` to track manual thermostat adjustments:

```yaml
# Configuration.yaml
input_number:
  manual_temp_adjustment:
    name: Manual Temperature Adjustment
    min: -5
    max: 5
    step: 0.5
    unit_of_measurement: "°C"
    mode: slider

# Customize.yaml
homeassistant:
  customize:
    input_number.manual_temp_adjustment:
      state_class: measurement

# Automation to track adjustments
automation:
  - alias: "Log Temperature Adjustment"
    trigger:
      platform: state
      entity_id: input_number.manual_temp_adjustment
    action:
      - service: logbook.log
        data:
          name: "Thermostat Adjustment"
          message: "Adjusted by {{ trigger.to_state.state }}°C"
```

Now you get statistics showing how often and how much you manually adjust temperatures!

## Summary: Where Statistics Appear

| Domain | Can Have Statistics? | Common Use |
|--------|---------------------|------------|
| `sensor` | ✅ Most common | Temperature, energy, power |
| `number` | ✅ Yes | Configuration values, setpoints |
| `input_number` | ✅ Yes (with customize) | User-adjustable values |
| `counter` | ✅ Yes (with customize) | Event counts |
| `binary_sensor` | ⚠️ Indirectly | Via template sensors tracking duration |
| `climate` | ❌ No (but attributes can) | Expose attributes as sensors |
| `light`, `switch` | ❌ No (on/off states) | Can track power via separate sensor |

## Key Takeaway

**Any entity** with:

- A numeric state
- A `unit_of_measurement`
- A `state_class` attribute

...can generate statistics, regardless of domain! The most common non-sensor examples are **`number`** and **`input_number`** entities used for tracking configuration changes, setpoints, and user inputs over time.
