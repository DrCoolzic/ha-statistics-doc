# Useful SQL queries for accessing states & state_attributes tables

This document provide a collection of SQL queries that can be used to retrieve data from the Home Assistant database. More specifically from the states and state_attributes tables.

## Database size information

```sql
-- SQLite database size
SELECT page_count * page_size / 1024.0 / 1024.0 as size_mb 
FROM pragma_page_count(), pragma_page_size();
```

## Count records in tables of interest

```sql
SELECT 'states_meta', COUNT(*) FROM states_meta
UNION ALL
SELECT 'states' as table_name, COUNT(*) as record_count FROM states
UNION ALL
SELECT 'state_attributes', COUNT(*) FROM state_attributes
UNION ALL
SELECT 'statistics_meta', COUNT(*) FROM statistics_meta:
```

Table | Count
--- | ---
states_meta | 234
states | 215463
state_attributes | 1780
statistics_meta | 78

## Top most active entities

```sql
SELECT 
    sm.entity_id,
    COUNT(*) as state_changes
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
GROUP BY sm.entity_id
ORDER BY state_changes DESC
LIMIT 10;
```

entity_id | state_changes
--- | ---
sensor.shellypro3em_3ce90e6eabdc_em0_power | 15344
sensor.shellypro3em_3ce90e6eabdc_em2_apparent_power | 15095
sensor.orange_livebox_data_received | 9428

## Find entities by type

```sql
-- find all sensors
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE 'sensor.%'
ORDER BY sm.entity_id
LIMIT 50;
```

---

## Get the latest state and old_state of all entities

```sql
-- SQLite version
SELECT 
    sm.entity_id,
    s.state,
    old_s.state as old_state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    datetime(s.last_changed_ts, 'unixepoch', 'localtime') as last_changed
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
INNER JOIN (
    SELECT metadata_id, MAX(state_id) as max_state_id
    FROM states
    GROUP BY metadata_id
) latest ON s.metadata_id = latest.metadata_id AND s.state_id = latest.max_state_id
LEFT JOIN states old_s ON s.old_state_id = old_s.state_id
ORDER BY sm.entity_id
LIMIT 50;
```

entity_id | state | old_state | last_updated
--- | --- | --- | ---
sensor.e3_vitocal_supply_pressure | 1.4 |  | 2/12/2026 13:15
sensor.e3_vitocal_supply_temperature | 39.8 | 39.3 | 2/15/2026 17:33
sensor.ecs_power | 1.6 | 1.8 | 2/15/2026 18:33

## Get the latest state and attributes of all entities

```sql
-- SQLite version
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    sa.shared_attrs as attributes
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
INNER JOIN (
    SELECT metadata_id, MAX(state_id) as max_state_id
    FROM states
    GROUP BY metadata_id
) latest ON s.metadata_id = latest.metadata_id AND s.state_id = latest.max_state_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
ORDER BY sm.entity_id
LIMIT 50;
```

entity_id | state | last_updated | attributes
--- | --- | --- | ---
number.e3_vitocal_comfort_heating_temperature | 22 | 2/12/2026 13:16 | {"unit_of_measurement":"Â°C","device_class":"temperature","friendly_name":"E3 Vitocal Comfort heating temperature"}
number.e3_vitocal_heating_curve_shift | -2 | 2/12/2026 13:16 | {"unit_of_measurement":"Â°C","device_class":"temperature","friendly_name":"E3 Vitocal Heating curve shift"}
number.e3_vitocal_heating_curve_slope | 1.2 | 2/12/2026 13:16 | {"friendly_name":"E3 Vitocal Heating curve slope"}

## Get state history for a specific entity

```sql
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    datetime(s.last_changed_ts, 'unixepoch', 'localtime') as last_changed
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
WHERE sm.entity_id = 'sensor.montry_temperature'
ORDER BY s.last_updated_ts DESC
LIMIT 50;
```

entity_id | state | last_updated
--- | --- | ---
sensor.montry_temperature | 4.1 | 2/15/2026 18:00
sensor.montry_temperature | 3.1 | 2/15/2026 17:00
sensor.montry_temperature | 2.6 | 2/15/2026 16:00

## Get state and attributes history for a specific entity

```sql
SELECT 
    sm.entity_id,
    s.state,
    sa.shared_attrs,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    datetime(COALESCE(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_a546b'
ORDER BY s.last_updated_ts DESC
LIMIT 50;
```

entity_id | state | shared_attrs | last_updated | last_changed
--- | --- | --- | --- | ---
device_tracker.sm_a546b | home | {"source_type":"gps","latitude":..} | 2/15/2026 18:42 | 2/15/2026 18:42
device_tracker.sm_a546b | home | {"source_type":"gps","latitude":...} | 2/15/2026 18:22 | 2/15/2026 18:22
device_tracker.sm_a546b | home | {"source_type":"gps","latitude":...} | 2/15/2026 18:17 | 2/15/2026 18:17

## Extract Specific JSON Fields

```sql
-- SQLite version
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    datetime(COALESCE(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed,
    JSON_EXTRACT(sa.shared_attrs, '$.latitude') as latitude,
    JSON_EXTRACT(sa.shared_attrs, '$.altitude') as altitude,
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC;
```

entity_id | state | last_updated | last_changed | latitude | altitude
--- | --- | --- | --- | --- | ---
device_tracker.sm_p620 | home | 2/12/2026 13:15 | 2/12/2026 13:15 | 4x.xx | 109
device_tracker.sm_p620 | home | 2/12/2026 13:10 | 2/12/2026 13:10 | 4x.xx | 109
device_tracker.sm_p620 | home | 2/12/2026 12:02 | 2/12/2026 12:02 | 4x.xx | 109

```sql
-- MariaDB version
SELECT 
    sm.entity_id,
    s.state,
    JSON_EXTRACT(sa.shared_attrs, '$.unit_of_measurement') as unit,
    JSON_EXTRACT(sa.shared_attrs, '$.state_class') as state_class,
    JSON_EXTRACT(sa.shared_attrs, '$.device_class') as device_class,
    FROM_UNIXTIME(s.last_updated_ts) as last_updated,
    FROM_UNIXTIME(COALESCE(s.last_changed_ts, s.last_updated_ts)) as last_changed
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'sensor.linky_east'
ORDER BY s.last_updated_ts DESC
LIMIT 50;
```

entity_id | state | last_updated | last_changed | unit | state_class | device_class
--- | --- | --- | --- | --- | --- | ---
sensor.linky_east | 73249536.0 | 2026-02-16 15:22:17.020967 | 2026-02-16 15:22:17.020967 | "Wh" | "total_increasing" | "energy"
sensor.linky_east | 73249568.0 | 2026-02-16 15:23:16.106835 | 2026-02-16 15:23:16.106835 | "Wh" | "total_increasing" | "energy"
sensor.linky_east | 73249504.0 | 2026-02-16 15:21:15.447930 | 2026-02-16 15:21:15.447930 | "Wh" | "total_increasing" | "energy"

## Show all available keys in the JSON object (MariaDB)

```sql
-- MariaDB version
SELECT 
    sm.entity_id,
    JSON_KEYS(sa.shared_attrs) as available_attributes,
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC
LIMIT 1;
```

## Get All Keys with Sample Values (SQLite)

```sql
SELECT 
    key,
    value,
    type
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id,
json_each(sa.shared_attrs)
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC
LIMIT 20;
```

key | value | type
--- | --- | ---
source_type | gps | text
latitude | 48.xx | real
longitude | 2.xx | real
gps_accuracy | 100 | integer
altitude | 109 | real

## Get Keys from Latest State Only (SQLite)

```sql
SELECT 
    key,
    value,
    type
FROM (
    SELECT sa.shared_attrs
    FROM states s
    INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
    LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
    WHERE sm.entity_id = 'device_tracker.sm_p620'
    ORDER BY s.last_updated_ts DESC
    LIMIT 1
),
json_each(shared_attrs)
ORDER BY key;
```

key | value | type
--- | --- | ---
altitude | 109 | real
friendly_name | SM-P620 | text
gps_accuracy | 100 | integer
longitude | 2.xxx | real

## Track movement between consecutive states (SQLite)

```sql
SELECT 
    sm.entity_id,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as timestamp,
    json_extract(sa.shared_attrs, '$.latitude') as lat,
    json_extract(sa.shared_attrs, '$.longitude') as lon,
    LAG(json_extract(sa.shared_attrs, '$.latitude')) OVER (ORDER BY s.last_updated_ts) as prev_lat,
    LAG(json_extract(sa.shared_attrs, '$.longitude')) OVER (ORDER BY s.last_updated_ts) as prev_lon,
    -- Approximate distance in meters (using simplified formula)
    ROUND(111320 * SQRT(
        POWER(json_extract(sa.shared_attrs, '$.latitude') - 
              LAG(json_extract(sa.shared_attrs, '$.latitude')) OVER (ORDER BY s.last_updated_ts), 2) +
        POWER((json_extract(sa.shared_attrs, '$.longitude') - 
              LAG(json_extract(sa.shared_attrs, '$.longitude')) OVER (ORDER BY s.last_updated_ts)) * 
              COS(json_extract(sa.shared_attrs, '$.latitude') * 3.14159 / 180), 2)
    ), 3) as distance_meters
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_a546b'
  AND json_extract(sa.shared_attrs, '$.latitude') IS NOT NULL
ORDER BY s.last_updated_ts DESC
LIMIT 200;
```

entity_id | timestamp | lat | lon | prev_lat | prev_lon | distance_meters
--- | --- | --- | --- | --- | --- | ---
device_tracker.sm_a546b | 2/17/2026 16:45 | 48.xx | 2.xx | 48.zz | 2.zz | 8.723
device_tracker.sm_a546b | 2/17/2026 16:43 | 48.xx | 2.xx | 48.zz | 2.zz | 12.09
device_tracker.sm_a546b | 2/17/2026 16:38 | 48.xx | 2.xx | 48.zz | 2.zz | 4.422
device_tracker.sm_a546b | 2/17/2026 16:38 | 48.xx | 2.xx | 48.zz | 2.zz | 3.656

## Display All Attributes with name/value/type

```sql
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    key as attribute_name,
    value as attribute_value,
    type as value_type
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id,
json_each(sa.shared_attrs)
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC
LIMIT 20;
```

entity_id | state | last_updated | attribute_name | attribute_value | value_type
--- | --- | --- | --- | --- | ---
device_tracker.sm_p620 | home | 2/12/2026 13:15 | source_type | gps | text
device_tracker.sm_p620 | home | 2/12/2026 13:15 | latitude | 48.xx | real
device_tracker.sm_p620 | home | 2/12/2026 13:15 | longitude | 2.xx | real
device_tracker.sm_p620 | home | 2/12/2026 13:15 | gps_accuracy | 100 | integer
device_tracker.sm_p620 | home | 2/12/2026 13:15 | altitude | 109 | real

## Retrieve state changes for an entity between specific dates

```sql
-- MariaDB version
SELECT 
    sm.entity_id,
    s.state,
    DATE_FORMAT(FROM_UNIXTIME(s.last_updated_ts), '%Y-%m-%d %H:%i:%s') as last_updated,
    DATE_FORMAT(FROM_UNIXTIME(COALESCE(s.last_changed_ts, s.last_updated_ts)), '%Y-%m-%d %H:%i:%s') as last_changed,
    -- DATE_FORMAT(FROM_UNIXTIME(IF(s.last_changed_ts IS NULL, s.last_updated_ts, s.last_changed_ts)) as last_changed
    DATE_FORMAT(FROM_UNIXTIME(s.last_reported_ts), '%Y-%m-%d %H:%i:%s') as last_reported
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
WHERE sm.entity_id = 'sensor.family_temperature'
  AND s.last_updated_ts BETWEEN 
    UNIX_TIMESTAMP('2026-01-27 12:00:00') 
    AND UNIX_TIMESTAMP('2026-01-27 13:00:00')
ORDER BY s.last_updated_ts;
```

```SQL
-- SQLite version
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    datetime(COALESCE(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed,
    datetime(s.last_changed_ts, 'unixepoch', 'localtime') as last_changed
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
WHERE sm.entity_id = 'sensor.montry_temperature'
  AND datetime(s.last_updated_ts, 'unixepoch', 'localtime') 
    BETWEEN '2026-01-25 12:00:00' AND '2026-01-27 13:00:00'
ORDER BY s.last_updated_ts ASC;
```

## All State changes in the last minute

```sql
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as timestamp
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
WHERE s.last_updated_ts > (strftime('%s', 'now') - 60)
ORDER BY s.last_updated_ts DESC;
```

entity_id | state | timestamp
--- | --- | ---
sensor.linky_sinsts | 3647 | 2/17/2026 18:21
sensor.linky_urms3 | 236 | 2/17/2026 18:21
sensor.linky_urms2 | 230 | 2/17/2026 18:21
sensor.linky_urms1 | 233 | 2/17/2026 18:21

## Get States with Pattern Matching

### Latest temperature sensor values

```sql
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
INNER JOIN (
    SELECT metadata_id, MAX(state_id) as max_state_id
    FROM states
    GROUP BY metadata_id
) latest ON s.metadata_id = latest.metadata_id AND s.state_id = latest.max_state_id
WHERE sm.entity_id LIKE '%temperature%'
ORDER BY sm.entity_id;
```

entity_id | state | last_updated
--- | --- | ---
sensor.e3_vitocal_boiler_supply_temperature | 47.2 | 2/17/2026 18:13
sensor.e3_vitocal_outside_temperature | 2.7 | 2/17/2026 18:23
sensor.e3_vitocal_primary_circuit_supply_temperature | 5.2 | 2/17/2026 18:06

### All climate and weather sensors (multiple pattern condition)

```sql
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE 'sensor.%'
  AND (
    sm.entity_id LIKE '%temperature%' 
    OR sm.entity_id LIKE '%humidity%'
    OR sm.entity_id LIKE '%pressure%'
  )
ORDER BY sm.entity_id;
```

```text
entity_id
sensor.e3_vitocal_supply_pressure
sensor.e3_vitocal_supply_temperature
sensor.micro_ondes_temperature
sensor.montry_humidity
sensor.montry_pressure
```

### Exclude certain patterns using NOT LIKE

```sql
-- All sensors containing "temperature" but not "battery"
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature%'
  AND sm.entity_id NOT LIKE '%battery%'
ORDER BY sm.entity_id;
```

### How many temperature entities do you have? (using count matches)

```sql
SELECT COUNT(DISTINCT sm.entity_id) as temperature_sensor_count
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature%';
```

```text
temperature_sensor_count
12
```
