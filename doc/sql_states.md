# Useful SQL Queries for accessing States & Attributes

- [Useful SQL Queries for accessing States \& Attributes](#useful-sql-queries-for-accessing-states--attributes)
  - [Database size information](#database-size-information)
  - [Count records in tables of interest](#count-records-in-tables-of-interest)
  - [Top most active entities](#top-most-active-entities)
  - [Find entities by type](#find-entities-by-type)
  - [Get the latest state and old\_state of all entities](#get-the-latest-state-and-old_state-of-all-entities)
  - [Get the latest state and attributes of all entities](#get-the-latest-state-and-attributes-of-all-entities)
  - [Get state history for a specific entity](#get-state-history-for-a-specific-entity)
  - [Get state and attributes history for a specific entity](#get-state-and-attributes-history-for-a-specific-entity)
  - [Extract Specific JSON Fields (e.g logitude, latitude)](#extract-specific-json-fields-eg-logitude-latitude)
    - [sql \& MySQL](#sql--mysql)
    - [MySQL specific](#mysql-specific)
  - [Show all available keys in the JSON object](#show-all-available-keys-in-the-json-object)
  - [Get All Keys with Sample Values -- sql](#get-all-keys-with-sample-values----sql)
  - [Get Keys from Latest State Only -- sql](#get-keys-from-latest-state-only----sql)
  - [Explore Nested JSON Structure (If you have nested JSON objects)](#explore-nested-json-structure-if-you-have-nested-json-objects)
  - [Track movement between consecutive states](#track-movement-between-consecutive-states)
  - [Display All Attributes with name/value/type](#display-all-attributes-with-namevaluetype)
    - [this query create a view](#this-query-create-a-view)
    - [Same query without creating a view](#same-query-without-creating-a-view)
  - [Retrieve state changes for an entity between specific dates](#retrieve-state-changes-for-an-entity-between-specific-dates)
    - [MySQL version](#mysql-version)
    - [SQLite version](#sqlite-version)
  - [All State changes in the last minute](#all-state-changes-in-the-last-minute)
  - [Get States with Pattern Matching\*\*](#get-states-with-pattern-matching)
    - [Latest temperature sensor values](#latest-temperature-sensor-values)
    - [All climate and weather sensors (multiple pattern condition)](#all-climate-and-weather-sensors-multiple-pattern-condition)
    - [Exclude certain patterns using NOT LIKE](#exclude-certain-patterns-using-not-like)
    - [How many temperature entities do you have? (using count matches)](#how-many-temperature-entities-do-you-have-using-count-matches)

---

## Database size information

```sql
SELECT page_count * page_size / 1024.0 / 1024.0 as size_mb 
FROM pragma_page_count(), pragma_page_size();
```

## Count records in tables of interest

```sql
SELECT 
    'states' as table_name, COUNT(*) as record_count FROM states
UNION ALL
SELECT 'statistics', COUNT(*) FROM statistics
UNION ALL
SELECT 'statistics_short_term', COUNT(*) FROM statistics_short_term;
```

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

## Find entities by type

```sql
-- find all sensors
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE 'sensor.%'
ORDER BY sm.entity_id;
```

## Get the latest state and old_state of all entities

```sql
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
ORDER BY sm.entity_id;
LIMIT 50;
```

## Get the latest state and attributes of all entities

```sql
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
ORDER BY sm.entity_id;
LIMIT 50;
```

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
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC
LIMIT 50;
```

## Extract Specific JSON Fields (e.g logitude, latitude)

### sql & MySQL

```sql
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    datetime(COALESCE(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed,
    JSON_EXTRACT(sa.shared_attrs, '$.latitude') as latitude,
    JSON_EXTRACT(sa.shared_attrs, '$.longitude') as longitude,
    sa.shared_attrs as full_attributes
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC;
```

### MySQL specific

```sql
SELECT 
    sm.entity_id,
    s.state,
    FROM_UNIXTIME(s.last_updated_ts) as last_updated,
    FROM_UNIXTIME(COALESCE(s.last_changed_ts, s.last_updated_ts)) as last_changed,
    sa.shared_attrs->'$.latitude' as latitude,  -- Returns JSON type
    -- sa.shared_attrs->>'$.latitude' as latitude_text,  -- Returns string/unquoted
    -- CAST(sa.shared_attrs->>'$.latitude' AS DECIMAL(10, 6)) as latitude, -- need to do math
    JSON_EXTRACT(sa.shared_attrs, '$.longitude') as longitude,
    sa.shared_attrs as full_attributes
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC;
```

## Show all available keys in the JSON object

```sql
SELECT 
    sm.entity_id,
    JSON_KEYS(sa.shared_attrs) as available_attributes,
    sa.shared_attrs as full_json
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC
LIMIT 1;
```

## Get All Keys with Sample Values -- sql

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

## Get Keys from Latest State Only -- sql

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

## Explore Nested JSON Structure (If you have nested JSON objects)

```SQL
SELECT 
    fullkey,
    value,
    type,
    path
FROM (
    SELECT sa.shared_attrs
    FROM states s
    INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
    LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
    WHERE sm.entity_id = 'device_tracker.sm_p620'
    ORDER BY s.last_updated_ts DESC
    LIMIT 1
),
json_tree(shared_attrs)
WHERE type != 'object'  -- Skip container objects, show only values
ORDER BY fullkey;
```

This shows the full path for nested values like:
  $.latitude → 48.8566
  $.longitude → 2.3522
  $.location.address.city → "Paris"
  $.location.address.country → "France"

## Track movement between consecutive states

```sql
SELECT 
    sm.entity_id,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as timestamp,
    json_extract(sa.shared_attrs, '$.latitude') as lat,
    json_extract(sa.shared_attrs, '$.longitude') as lon,
    LAG(json_extract(sa.shared_attrs, '$.latitude')) OVER (ORDER BY s.last_updated_ts) as prev_lat,
    LAG(json_extract(sa.shared_attrs, '$.longitude')) OVER (ORDER BY s.last_updated_ts) as prev_lon,
    -- Approximate distance in meters (using simplified formula)
    111320 * SQRT(
        POWER(json_extract(sa.shared_attrs, '$.latitude') - 
              LAG(json_extract(sa.shared_attrs, '$.latitude')) OVER (ORDER BY s.last_updated_ts), 2) +
        POWER((json_extract(sa.shared_attrs, '$.longitude') - 
              LAG(json_extract(sa.shared_attrs, '$.longitude')) OVER (ORDER BY s.last_updated_ts)) * 
              COS(json_extract(sa.shared_attrs, '$.latitude') * 3.14159 / 180), 2)
    ) as distance_meters
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_a546b'
  AND json_extract(sa.shared_attrs, '$.latitude') IS NOT NULL
ORDER BY s.last_updated_ts DESC
LIMIT 20;
```

## Display All Attributes with name/value/type

### this query create a view

```sql
WITH device_tracker_attributes AS (
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
    WHERE sm.entity_id LIKE 'device_tracker.%'
)
SELECT * 
FROM device_tracker_attributes 
WHERE entity_id = 'device_tracker.sm_p620'
ORDER BY last_updated DESC
LIMIT 20;
```

### Same query without creating a view

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

## Retrieve state changes for an entity between specific dates

### MySQL version

```sql
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

### SQLite version

```SQL
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    --datetime(COALESCE(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed
    datetime(IFNULL(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed,
    datetime(s.last_reported_ts, 'unixepoch', 'localtime') as last_reported
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
WHERE sm.entity_id = 'sensor.montry_temperature'
  AND s.last_updated_ts BETWEEN 
    strftime('%s', '2026-01-25 12:00:00') 
    AND strftime('%s', '2026-01-27 13:00:00')
ORDER BY s.last_updated_ts;
```

Alternative query

```sql
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

## Get States with Pattern Matching**

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
