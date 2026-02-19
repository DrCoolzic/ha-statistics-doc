# Appendix 3: Setting Units of Measurement

!!! Danger "Under construction - Probably contains inaccurate information"
    THIS PART STILL NEEDS TO BE REVIEWED/CORRECTED

## Overview

Home Assistant has a complex system for determining what unit a sensor uses internally and what unit is displayed to the user. This system involves multiple layers: native units, suggested units, unit translation, user preferences, and statistics enforcement. Understanding this hierarchy is crucial for configuring sensors correctly and troubleshooting display issues.

---

## Part 1: Internal Unit Selection (Storage)

### The Unit Selection Hierarchy

When a sensor is first created in Home Assistant, the system determines its internal unit through a precedence chain:

```text
1. Sensor's unit_of_measurement property
   ↓ (if not set)
2. Sensor's suggested_unit_of_measurement 
   ↓ (if not set)
3. Sensor's native_unit_of_measurement
   ↓ (if not set)
4. No unit (state only, no unit-aware features)
```

### Understanding the Three Unit Properties

#### 1. `native_unit_of_measurement`

**What it is:**

- The "raw" unit that the sensor/integration actually measures
- The unit of the underlying hardware or data source
- Cannot be changed without modifying integration code

**Example:**

```python
# In integration code (e.g., ESPHome component)
class EnergySensor(SensorEntity):
    @property
    def native_unit_of_measurement(self):
        return "Wh"  # Sensor hardware reports in Wh
    
    @property
    def native_value(self):
        return self._raw_value  # Raw value from hardware
```

**User control:** ❌ None (integration-defined)

#### 2. `suggested_unit_of_measurement`

**What it is:**

- Integration's recommendation for display/storage unit
- A "hint" to Home Assistant: "I report in X, but you might prefer Y"
- Used for automatic unit conversion

**Example:**

```python
# In integration code
class EnergySensor(SensorEntity):
    @property
    def native_unit_of_measurement(self):
        return "Wh"  # Hardware reports Wh
    
    @property
    def suggested_unit_of_measurement(self):
        return "kWh"  # But suggest displaying in kWh (more readable)
```

**Result:**

- Home Assistant receives: 72500000 Wh (native)
- Home Assistant stores in entity registry: kWh (suggested)
- Home Assistant converts for display: 72500 kWh
- Statistics recorded in: kWh

**User control:** ⚠️ Limited (can override via entity settings, but it may not work - see Part 2)

#### 3. `unit_of_measurement` (Explicit)

**What it is:**

- Direct specification of unit (bypasses native/suggested)
- Used in YAML configurations, template sensors, etc.
- Highest priority if explicitly set

**Example:**

```yaml
# Template sensor
template:
  - sensor:
      - name: "Energy Total"
        unit_of_measurement: "kWh"  # Explicit unit
        state: "{{ states('sensor.raw_energy') | float / 1000 }}"
```

**User control:** ✅ Full (you define it in configuration)

### Where Units Are Stored Initially

When a sensor is first added:

```text
Integration provides:
├── native_unit_of_measurement: "Wh"
├── suggested_unit_of_measurement: "kWh"
└── (optional) explicit unit_of_measurement

Home Assistant processes:
1. Checks for explicit unit_of_measurement → Use if present
2. Else checks suggested_unit_of_measurement → Use if present  
3. Else uses native_unit_of_measurement → Fallback
4. Else no unit → State-only entity

Stores in Entity Registry:
{
  "unit_of_measurement": "kWh",  ← Chosen unit
  "original_device_class": "energy",
  "options": {
    "sensor": {
      "suggested_unit_of_measurement": "kWh"  ← Reference
    }
  }
}

Eventually creates Statistics Metadata:
statistics_meta {
  statistic_id: "sensor.energy_total",
  unit_of_measurement: "kWh"  ← Locked in once created
}
```

---

## Part 2: Unit Translation & Display

### What is Unit Translation?

**Unit translation** is Home Assistant's ability to:

- Store data in one unit internally
- Display it in a different unit to the user
- Automatically convert between compatible units

**Introduced:** 2022.9+ (for statistics)  
**Documentation:** [Developer Blog - Statistics Refactoring](https://developers.home-assistant.io/blog/2022/09/29/statistics_refactoring/)

### Compatible Unit Families

Home Assistant knows about unit families and can convert within them:

| Family | Units | Example Conversion |
|--------|-------|-------------------|
| **Energy** | Wh, kWh, MWh, GWh | 1000 Wh = 1 kWh |
| **Power** | W, kW, MW | 1000 W = 1 kW |
| **Temperature** | °C, °F, K | 20°C = 68°F |
| **Pressure** | Pa, hPa, bar, mbar, psi, inHg, mmHg | 1013 hPa = 1.013 bar |
| **Distance** | mm, cm, m, km, in, ft, yd, mi | 1000 m = 1 km |
| **Volume** | mL, L, gal (US/UK), fl oz, cu ft, cu m | 1000 mL = 1 L |
| **Speed** | m/s, km/h, mph, ft/s, kn | 1 m/s = 3.6 km/h |
| **Mass** | g, kg, mg, µg, oz, lb, st | 1000 g = 1 kg |

**Requirements for translation:**

1. ✅ Sensor must have `device_class` set
2. ✅ Sensor must have `unique_id` (allows entity customization)
3. ✅ Units must be in the same family

### How Unit Translation Works

#### Example: Energy Sensor

**Integration configuration:**

```python
# ESPHome sends Wh
class EnergySensor(SensorEntity):
    _attr_device_class = SensorDeviceClass.ENERGY
    _attr_state_class = SensorStateClass.TOTAL_INCREASING
    _attr_native_unit_of_measurement = "Wh"
    _attr_suggested_unit_of_measurement = "kWh"
    _attr_unique_id = "energy_meter_001"
```

**What happens:**

```text
1. Hardware reports: 72500000 Wh (native)
   ↓
2. HA sees suggested_unit_of_measurement: kWh
   ↓
3. HA converts: 72500000 Wh ÷ 1000 = 72500 kWh
   ↓
4. Stores in entity registry: unit = "kWh"
   ↓
5. Creates statistics_meta: unit = "kWh"
   ↓
6. Records statistics: state = 72500 (in kWh)
   ↓
7. User sees in UI: "72500 kWh"
```

**User can change display unit:**

Settings → Entities → sensor.energy_meter → ⚙️ → Unit of measurement → Select "MWh"

**Result:**

```text
Statistics still stored: 72500 (kWh scale)
   ↓
HA converts for display: 72500 ÷ 1000 = 72.5 MWh
   ↓
User sees: "72.5 MWh"
```

**BUT:** This only works if statistics don't exist yet! (See caveats below)

---

## Part 3: The Reality - What Actually Happens

### Scenario A: Brand New Sensor (No Statistics)

**Timeline:**

1. **Sensor added to HA:**

   ```yaml
   sensor:
     - platform: integration_name
       name: "Power Meter"
       # Integration defines: native=W, suggested=kW, device_class=power
   ```

2. **Entity Registry created:**

   ```json
   {
     "entity_id": "sensor.power_meter",
     "unique_id": "power_meter_001",
     "unit_of_measurement": "kW",  ← suggested unit used
     "original_device_class": "power"
   }
   ```

3. **User can customize:**
   - Settings → Entities → sensor.power_meter → ⚙️
   - Change "Unit of measurement" to "W"
   - ✅ **This works!** (no statistics yet to conflict)

4. **Statistics created (after 5-10 min):**

   ```sql
   INSERT INTO statistics_meta (statistic_id, unit_of_measurement)
   VALUES ('sensor.power_meter', 'W');  -- Uses entity registry value
   ```

5. **Going forward:**
   - Display: W
   - Storage: W
   - User preference respected ✓

### Scenario B: Existing Sensor (With Statistics)

**Timeline:**

1. **Sensor already exists with statistics:**

   ```sql
   SELECT * FROM statistics_meta WHERE statistic_id = 'sensor.power_meter';
   
   | id | statistic_id         | unit  |
   |----|----------------------|-------|
   | 42 | sensor.power_meter   | kW    |
   ```

2. **User tries to change:**
   - Settings → Entities → sensor.power_meter → ⚙️
   - Change "Unit of measurement" to "W"
   - Click "Update"

3. **Entity Registry updates:**

   ```json
   {
     "options": {
       "sensor": {
         "unit_of_measurement": "W"  ← Updated
       }
     }
   }
   ```

4. **But nothing else changes:**
   - statistics_meta: Still shows kW ❌
   - Display: Still shows kW ❌
   - New statistics: Still recorded in kW ❌
   - Entity registry change **ignored**!

5. **Why?**

   ```text
   ┌─────────────────────────────────────┐
   │ statistics_meta.unit_of_measurement │
   │ Takes precedence over EVERYTHING    │
   │ Once created, it's "locked in"      │
   └─────────────────────────────────────┘
   ```

### Scenario C: Template Sensor with Unit Translation

**Configuration:**

```yaml
template:
  - sensor:
      - name: "Outside Temperature"
        unique_id: temp_outside_001
        device_class: temperature
        state_class: measurement
        unit_of_measurement: "°C"  # You define as Celsius
        state: "{{ states('sensor.raw_temp') }}"
```

**User wants to see °F:**

**Option 1: Via Entity Settings (if no statistics)**

- Settings → Entities → sensor.outside_temperature → ⚙️
- Change "Unit of measurement" to "°F"
- ✅ Works if statistics don't exist yet
- Display converts: 20°C → 68°F

**Option 2: Via Template (always works)**

```yaml
template:
  - sensor:
      - name: "Outside Temperature F"
        unique_id: temp_outside_f_001
        device_class: temperature
        state_class: measurement
        unit_of_measurement: "°F"  # Define as Fahrenheit from start
        state: "{{ (states('sensor.raw_temp') | float * 9/5) + 32 }}"
```

**Option 3: Customize (display only, doesn't affect statistics)**

```yaml
homeassistant:
  customize:
    sensor.outside_temperature:
      unit_of_measurement: "°F"  # Display override
```

⚠️ **Warning:** Option 3 changes displayed unit but NOT the values!

- If sensor reports 20°C
- Customization shows "20 °F" ← Wrong! (Should be 68)
- This is misleading and not recommended

---

## Part 4: User Control Over Units

### What Users CAN Control

#### 1. Template Sensors (Full Control)

```yaml
template:
  - sensor:
      - name: "My Energy Sensor"
        unique_id: my_energy_001
        unit_of_measurement: "kWh"  # ← YOU decide
        device_class: energy
        state_class: total_increasing
        state: "{{ states('sensor.source') | float / 1000 }}"  # Convert Wh→kWh
```

**Control level:** ✅✅✅ Complete

- You define unit
- You perform conversion
- You control statistics unit (indirectly)

#### 2. Integration Configuration (Varies)

Some integrations allow unit customization:

```yaml
# Example: Some integrations have options
sensor:
  - platform: some_integration
    unit: "kWh"  # If integration supports it
```

**Control level:** ⚠️ Depends on integration

- Check integration documentation
- Not all integrations support this

#### 3. Entity Settings (Before Statistics Exist)

Settings → Entities → [sensor] → ⚙️ → Unit of measurement

**Control level:** ⚠️ Limited window

- ✅ Works if sensor is new
- ❌ Ignored once statistics exist
- ⚠️ Timing-dependent

#### 4. Statistics Metadata (SQL)

```sql
UPDATE statistics_meta 
SET unit_of_measurement = 'kWh'
WHERE statistic_id = 'sensor.my_sensor';
```

**Control level:** ✅ Effective but requires:

- SQL knowledge
- Database backup
- Converting existing data
- Understanding consequences

### What Users CANNOT Control

#### 1. Integration's Native Unit

**Example: ESPHome sensor reports Wh**

You cannot change this without:

- Modifying ESPHome device configuration
- Or using a template sensor to convert

**Why:** This is defined in the integration's code.

#### 2. Existing Statistics Unit (Without SQL)

Once `statistics_meta` has a unit, it's locked.

**Why:** Home Assistant has no UI feature to change this safely (would require data conversion).

#### 3. Device Class Behavior

If `device_class: energy`, HA will:

- Enforce energy unit family (Wh/kWh/MWh)
- Reject incompatible units (e.g., °C)
- Apply unit normalization rules

**Why:** Device classes have built-in semantics.

---

## Part 5: Practical Examples

### Example 1: ESPHome Energy Sensor - Wh to kWh

**Goal:** ESPHome reports Wh, but you want kWh in Home Assistant.

**Method A: Let Integration Handle It**

ESPHome configuration:

```yaml
sensor:
  - platform: pulse_counter
    name: "Energy Meter"
    # Sensor reports in Wh (native)
    unit_of_measurement: "Wh"
    device_class: energy
    state_class: total_increasing
```

**Result:**

- ESPHome sends: Wh
- If integration has `suggested_unit_of_measurement: kWh`, HA converts automatically
- Check if this happens by looking at Developer Tools → States

**Method B: Template Sensor Conversion**

```yaml
# In Home Assistant configuration.yaml
template:
  - sensor:
      - name: "Energy Meter kWh"
        unique_id: energy_meter_kwh_001
        unit_of_measurement: "kWh"
        device_class: energy
        state_class: total_increasing
        state: "{{ states('sensor.energy_meter') | float(0) / 1000 }}"
        availability: "{{ states('sensor.energy_meter') not in ['unavailable', 'unknown'] }}"
```

**Result:**

- Original sensor: 72500 Wh
- Template sensor: 72.5 kWh
- Statistics for template sensor: Recorded in kWh
- ✅ Full control

**Method C: ESPHome Calculation**

```yaml
# In ESPHome device configuration
sensor:
  - platform: pulse_counter
    id: energy_wh
    # ... configuration ...
    unit_of_measurement: "Wh"
    internal: true  # Hide the Wh sensor
    
  - platform: template
    name: "Energy Meter"
    unit_of_measurement: "kWh"
    device_class: energy
    state_class: total_increasing
    lambda: return id(energy_wh).state / 1000.0;
```

**Result:**

- ESPHome sends to HA: kWh directly
- No conversion needed in HA
- ✅ Clean and efficient

### Example 2: Temperature Sensor - °C Display, °F Storage

**Goal:** Sensor reports °C, but you want to store statistics in °F.

**Not recommended, but possible:**

```yaml
template:
  - sensor:
      - name: "Room Temperature"
        unique_id: room_temp_f_001
        unit_of_measurement: "°F"  # Store in °F
        device_class: temperature
        state_class: measurement
        state: "{{ (states('sensor.room_temp_c') | float(0) * 9/5) + 32 }}"
```

**Better approach:** Store in °C, display in °F via unit translation

```yaml
template:
  - sensor:
      - name: "Room Temperature"
        unique_id: room_temp_c_001
        unit_of_measurement: "°C"  # Store in °C (international standard)
        device_class: temperature
        state_class: measurement
        state: "{{ states('sensor.raw_temp') }}"
```

Then (if no statistics exist yet):

- Settings → Entities → sensor.room_temperature → ⚙️
- Change unit to "°F"
- HA will convert display automatically

### Example 3: Power Sensor - W to kW

**Goal:** Integration reports W, graphs are hard to read (large numbers).

**Method: Template Sensor**

```yaml
template:
  - sensor:
      - name: "House Power kW"
        unique_id: house_power_kw_001
        unit_of_measurement: "kW"
        device_class: power
        state_class: measurement
        state: "{{ (states('sensor.house_power') | float(0) / 1000) | round(2) }}"
        availability: "{{ is_number(states('sensor.house_power')) }}"
```

**Result:**

- Original: 2500 W
- Template: 2.5 kW
- Graphs show: 0-5 kW (much more readable than 0-5000 W)

### Example 4: Utility Meter with Unit Selection

**Goal:** Track daily energy, ensure correct unit.

```yaml
utility_meter:
  daily_energy:
    source: sensor.energy_meter_kwh  # ← Use sensor already in kWh!
    cycle: daily
    
# The utility meter inherits the source sensor's unit
# Result: daily_energy sensor will also be in kWh
```

⚠️ **Don't do this:**

```yaml
utility_meter:
  daily_energy:
    source: sensor.energy_meter  # In Wh
    cycle: daily
    
template:
  - sensor:
      - name: "Daily Energy kWh"
        unit_of_measurement: "kWh"
        # This shows kWh but values are Wh scale - WRONG!
        state: "{{ states('sensor.daily_energy') }}"
```

---

## Part 6: Decision Matrix

### "Which method should I use?"

Use this table to decide how to handle units:

| Situation | Recommended Method | Reason |
|-----------|-------------------|--------|
| **New template sensor** | Set `unit_of_measurement` directly | Full control from start |
| **ESPHome sensor** | Convert in ESPHome config | Cleaner, less HA overhead |
| **Integration with config** | Check integration docs | May support unit selection |
| **Need different display unit** | Template sensor + conversion | Reliable, always works |
| **Already has statistics** | See [Part X: Changing Units]( apdx4_change_units.md) | Complex, requires SQL |
| **Multiple conversions needed** | Create multiple template sensors | One per unit |
| **Just want display change** | Try entity settings (if no stats) | May work if lucky |

### Template Sensor vs Unit Translation

| Aspect | Template Sensor | Unit Translation |
|--------|----------------|------------------|
| **Control** | ✅ Complete | ⚠️ Limited |
| **Reliability** | ✅ Always works | ⚠️ Depends on timing |
| **Setup complexity** | Medium (requires YAML) | Easy (UI) |
| **Conversion control** | ✅ You define formula | ❌ HA decides |
| **Multiple units** | ✅ Create multiple sensors | ⚠️ One at a time via UI |
| **Statistics persistence** | ✅ Unit locked at creation | ⚠️ Can conflict later |
| **Best for** | Production use | Experimenting |

**Recommendation:** Use template sensors for important sensors where you need guaranteed unit control.

---

## Part 7: Troubleshooting Unit Issues

### Problem: "Unit keeps changing back"

**Symptoms:**

- Set unit to Wh via entity settings
- Restarts show kWh again

**Diagnosis:**

```sql
-- Check statistics metadata
SELECT unit_of_measurement 
FROM statistics_meta 
WHERE statistic_id = 'sensor.your_sensor';
```

If this shows kWh, that's your answer.

**Solution:** See [Part X: Changing Units]( apdx4_change_units.md)

### Problem: "Values don't match unit"

**Symptoms:**

- Unit shows "kWh"
- But values like 72500 (should be ~72)

**Diagnosis:**

- Integration sending Wh
- Display showing kWh label
- No conversion happening

**Check:**

```yaml
# Developer Tools → States
sensor.energy_meter:
  state: 72500
  unit_of_measurement: kWh  ← Label says kWh
  # But value is clearly Wh scale!
```

**Solution:** Create proper template sensor with conversion:

```yaml
template:
  - sensor:
      - name: "Energy Meter Corrected"
        unique_id: energy_corrected_001
        unit_of_measurement: "kWh"
        device_class: energy
        state_class: total_increasing
        state: "{{ states('sensor.energy_meter') | float(0) / 1000 }}"
```

### Problem: "Can't select desired unit in dropdown"

**Symptoms:**

- Entity settings show unit dropdown
- But desired unit not in list (e.g., want MWh, only see Wh/kWh)

**Cause:** Unit not in default conversion list for that device_class

**Solutions:**

**Option 1:** Template sensor with explicit unit

```yaml
template:
  - sensor:
      - name: "Energy MWh"
        unique_id: energy_mwh_001
        unit_of_measurement: "MWh"
        device_class: energy
        state_class: total_increasing
        state: "{{ states('sensor.energy_kwh') | float(0) / 1000 }}"
```

**Option 2:** Remove device_class (if you don't need energy dashboard integration)

```yaml
template:
  - sensor:
      - name: "Energy Custom"
        unique_id: energy_custom_001
        unit_of_measurement: "MWh"  # Any unit you want
        # No device_class = no unit family restrictions
        state_class: total_increasing
        state: "{{ states('sensor.energy_kwh') | float(0) / 1000 }}"
```

### Problem: "Integration changed, now unit is wrong"

**Symptoms:**

- Integration updated
- Now reports different unit
- Old statistics incompatible

**Example:**

- Old version: Reported W
- New version: Reports kW
- Statistics: Still expect W

**Solution:**

Either accept discontinuity or migrate statistics:

```sql
-- Convert W → kW
UPDATE statistics
SET mean = mean / 1000, min = min / 1000, max = max / 1000
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.power');

UPDATE statistics_meta
SET unit_of_measurement = 'kW'
WHERE statistic_id = 'sensor.power';
```

---

## Part 8: Best Practices

### 1. Choose Units at Sensor Creation

```yaml
# ✅ GOOD: Explicit from the start
template:
  - sensor:
      - name: "Solar Production"
        unique_id: solar_prod_kwh_001
        unit_of_measurement: "kWh"  # Chosen deliberately
        device_class: energy
        state_class: total_increasing
        # Comment explaining choice:
        # Using kWh to match utility billing
        # DO NOT CHANGE - Statistics created 2025-01-15
        state: "{{ (states('sensor.solar_wh') | float / 1000) | round(3) }}"
```

```yaml
# ❌ BAD: Vague, might change later
template:
  - sensor:
      - name: "Solar"
        state: "{{ states('sensor.raw') }}"
```

### 2. Document Unit Choices

```yaml
# configuration.yaml

# ═══════════════════════════════════════════════════════
# ENERGY SENSORS - Unit Decisions
# ═══════════════════════════════════════════════════════
# All energy sensors use kWh for consistency with utility bills
# DO NOT change units after statistics are created
# If you need different units, create NEW template sensors

template:
  - sensor:
      # Main energy sensor - kWh
      - name: "House Energy Total"
        unit_of_measurement: "kWh"
        # ...
        
      # Daily reset helper - also kWh
      - name: "House Energy Today"
        unit_of_measurement: "kWh"
        # ...
```

### 3. Use Consistent Units Across Related Sensors

```yaml
# ✅ GOOD: All power sensors in kW
template:
  - sensor:
      - name: "Solar Power"
        unit_of_measurement: "kW"
      - name: "Grid Power"
        unit_of_measurement: "kW"
      - name: "House Power"
        unit_of_measurement: "kW"
      - name: "Net Power"
        unit_of_measurement: "kW"
        state: >
          {{ (states('sensor.solar_power') | float(0) 
            - states('sensor.house_power') | float(0)) | round(2) }}
```

```yaml
# ❌ BAD: Mixed units - calculations won't work
template:
  - sensor:
      - name: "Solar Power"
        unit_of_measurement: "W"
      - name: "Grid Power"
        unit_of_measurement: "kW"  # Different!
      - name: "Net Power"
        # This calculation is WRONG - mixing W and kW
        state: >
          {{ states('sensor.solar_power') | float(0)
            - states('sensor.grid_power') | float(0) }}
```

### 4. Create Conversion Template Sensors

```yaml
# Keep original sensor, create converted versions
template:
  - sensor:
      # Original (from integration)
      # - name: "Power Meter"  ← Already exists, reports W
      
      # Converted version for better readability
      - name: "Power Meter kW"
        unique_id: power_meter_kw_001
        unit_of_measurement: "kW"
        device_class: power
        state_class: measurement
        state: "{{ (states('sensor.power_meter') | float(0) / 1000) | round(3) }}"
        
      # Hide original, use converted version
      # Settings → Entities → sensor.power_meter → Toggle "Enabled"
```

### 5. Test Before Adding state_class

```yaml
# Step 1: Create sensor WITHOUT state_class
template:
  - sensor:
      - name: "Test Sensor"
        unique_id: test_001
        unit_of_measurement: "kWh"
        device_class: energy
        # state_class: total_increasing  ← Commented out
        state: "{{ states('sensor.source') | float / 1000 }}"
```

**Verify:**

- Check Developer Tools → States
- Verify unit shows correctly
- Verify values are in correct scale
- Wait a few cycles, ensure no errors

```yaml
# Step 2: Add state_class only after verification
template:
  - sensor:
      - name: "Test Sensor"
        unique_id: test_001
        unit_of_measurement: "kWh"
        device_class: energy
        state_class: total_increasing  # ← Now enable statistics
        state: "{{ states('sensor.source') | float / 1000 }}"
```

### 6. Use Availability Templates

```yaml
template:
  - sensor:
      - name: "Energy kWh"
        unit_of_measurement: "kWh"
        state: "{{ states('sensor.energy_wh') | float(0) / 1000 }}"
        # Prevent invalid states from creating bad statistics
        availability: >
          {{ states('sensor.energy_wh') not in ['unavailable', 'unknown']
             and is_number(states('sensor.energy_wh')) }}
```

---

## Part 9: Summary & Quick Reference

### Key Concepts

1. **Three unit properties:** native, suggested, explicit (`unit_of_measurement`)
2. **Entity registry stores user preference** (but it may be ignored)
3. **Statistics metadata controls reality** (once created, it's king)
4. **Unit translation exists** (but timing-dependent and unreliable)
5. **Template sensors give full control** (recommended for production)

### Quick Decision Guide

**"I'm creating a new sensor, what unit should I use?"**

→ Choose based on:

- Utility bill compatibility (energy/water/gas)
- Readability (avoid very large/small numbers)
- Industry standards
- Personal preference (temperature)

**"I want to change an existing sensor's unit"**

→ Does it have statistics?

- **No:** Try entity settings (may work)
- **Yes:** See [Changing Units document]( apdx4_change_units.md) (requires SQL or deletion)

**"Integration reports wrong unit for me"**

→ Create template sensor with conversion:

```yaml
template:
  - sensor:
      - name: "Sensor Converted"
        unit_of_measurement: "your_preferred_unit"
        state: "{{ states('sensor.original') | float * conversion_factor }}"
```

**"I want multiple units displayed"**

→ Create multiple template sensors:

```yaml
template:
  - sensor:
      - name: "Temp Celsius"
        unit_of_measurement: "°C"
        state: "{{ states('sensor.raw') }}"
      
      - name: "Temp Fahrenheit"
        unit_of_measurement: "°F"
        state: "{{ (states('sensor.raw') | float * 9/5) + 32 }}"
```

### Common Conversion Formulas

```yaml
# Energy: Wh ↔ kWh
kWh_from_Wh: "{{ wh_value | float / 1000 }}"
Wh_from_kWh: "{{ kwh_value | float * 1000 }}"

# Energy: kWh ↔ MWh
MWh_from_kWh: "{{ kwh_value | float / 1000 }}"
kWh_from_MWh: "{{ mwh_value | float * 1000 }}"

# Power: W ↔ kW
kW_from_W: "{{ w_value | float / 1000 }}"
W_from_kW: "{{ kw_value | float * 1000 }}"

# Temperature: °C ↔ °F
F_from_C: "{{ (c_value | float * 9 / 5) + 32 }}"
C_from_F: "{{ (f_value | float - 32) * 5 / 9 }}"

# Temperature: °C ↔ K
K_from_C: "{{ c_value | float + 273.15 }}"
C_from_K: "{{ k_value | float - 273.15 }}"

# Pressure: hPa ↔ bar
bar_from_hPa: "{{ hpa_value | float / 1000 }}"
hPa_from_bar: "{{ bar_value | float * 1000 }}"

# Distance: m ↔ km
km_from_m: "{{ m_value | float / 1000 }}"
m_from_km: "{{ km_value | float * 1000 }}"

# Volume: mL ↔ L
L_from_mL: "{{ ml_value | float / 1000 }}"
mL_from_L: "{{ l_value | float * 1000 }}"
```

---

## Related Documentation

- **[Appendix 4: Changing Units of Measurement]( apdx4_change_units.md)** - Detailed guide for existing sensors
- **[Part 1: Foundational Concepts](part1_fundamental_concepts.md)** - Understanding entities and states
- **[Part 2: Statistics Generation](part2_statistics_generation.md)** - How statistics are created
- **[Part 4: Best Practices](part4_practices_troubleshooting.md)** - Choosing state_class correctly

---

<div class="nav-prevnext" markdown="0">
  <a href="../apdx2_stat_domains/" class="nav-prev">
    <span class="nav-label">Previous</span>
    <span class="nav-title">« Appendix 2: Statistics Domains</span>
  </a>
  <a href="../apdx4_change_units/" class="nav-next">
    <span class="nav-label">Next</span>
    <span class="nav-title">Appendix 4: Changing Units of Measurement »</span>
  </a>
</div>
