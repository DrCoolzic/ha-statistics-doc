# Useful SQL Queries for accessing statistics

## General Queries

### Database size information

```
SELECT page_count * page_size / 1024.0 / 1024.0 as size_mb 
FROM pragma_page_count(), pragma_page_size();
```

### Count records in tables of interest

```
SELECT 
    'states' as table_name, COUNT(*) as record_count FROM states
UNION ALL
SELECT 'statistics', COUNT(*) FROM statistics
UNION ALL
SELECT 'statistics_short_term', COUNT(*) FROM statistics_short_term;
```

---

## Accessing States information

### Get the latest state and old state of all entities

```sqlite
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

### Get the latest state and attributes of all entities

```sqlite
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

### Get history for a specific entity

```
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

### Retrieve state changes for an entity between specific dates -- MySQL version

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

### Retrieve state changes for an entity between specific dates -- SQLite version

```sqlite
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

```sqlite
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



### All State change in the last minute

```
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as timestamp
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
WHERE s.last_updated_ts > (strftime('%s', 'now') - 60)
ORDER BY s.last_updated_ts DESC;
```

## **Entity Statistics**

### Top 10 most active entities

```
SELECT 
    sm.entity_id,
    COUNT(*) as state_changes
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
GROUP BY sm.entity_id
ORDER BY state_changes DESC
LIMIT 10;
```

### Find entities by type (e.g., all sensors)

```
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE 'sensor.%'
ORDER BY sm.entity_id;
```

---

## Accessing Statistics Information



### Retrieve measurement statistics between specific dates -- MySQL version

```sql
SELECT 
    sm.statistic_id,
    CONVERT_TZ(FROM_UNIXTIME(s.start_ts), '+00:00', @@session.time_zone) as period_start,
    CONVERT_TZ(FROM_UNIXTIME(s.created_ts), '+00:00', @@session.time_zone) as created_at,
    s.mean,
    s.min,
    s.max
FROM statistics_short_term s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.family_temperature'
  AND CONVERT_TZ(FROM_UNIXTIME(s.start_ts), '+00:00', @@session.time_zone) >= '2026-01-27 13:00:00'
  AND CONVERT_TZ(FROM_UNIXTIME(s.start_ts), '+00:00', @@session.time_zone) < '2026-01-27 14:00:00'
ORDER BY s.start_ts ASC;
```

### Retrieve measurement statistics between specific dates  -- SQLite version

```sqlite
SELECT 
    sm.statistic_id,
    datetime(s.start_ts, 'unixepoch', 'localtime') as period_start,
    datetime(s.created_ts, 'unixepoch', 'localtime') as created_at,
    s.mean,
    s.min,
    s.max
FROM statistics_short_term s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.linky_sinsts'
  AND datetime(s.start_ts, 'unixepoch', 'localtime') >= '2026-01-27 13:00:00'
  AND datetime(s.start_ts, 'unixepoch', 'localtime') < '2026-01-27 14:00:00'
ORDER BY s.start_ts ASC;
```

### Get average/min/max from measurement statistics

```
SELECT 
    sm.statistic_id,
    AVG(s.mean) as avg_value,
    MIN(s.min) as min_value,
    MAX(s.max) as max_value
FROM statistics s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.montry_temperature'
  AND s.start_ts > (strftime('%s', 'now') - 604800) -- last 7 days
GROUP BY sm.statistic_id;
```

### Retrieve counter statistics between specific dates  -- SQLite version

Retrieve information and compute delta (growth) information

```sqlite
SELECT 
    sm.statistic_id,
    datetime(s.start_ts, 'unixepoch', 'localtime') as period_start,
    datetime(s.created_ts, 'unixepoch', 'localtime') as created_at,
    s.state,
    s.sum,
    s.sum - LAG(s.sum) OVER (ORDER BY s.start_ts) as period_delta,
    datetime(s.last_reset_ts, 'unixepoch', 'localtime') as last_reset
FROM statistics_short_term s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.linky_east'
  AND datetime(s.start_ts, 'unixepoch', 'localtime') >= '2026-01-27 13:00:00'
  AND datetime(s.start_ts, 'unixepoch', 'localtime') < '2026-01-27 14:00:00'
ORDER BY s.start_ts ASC;
```

### **Get All Statistics for a day (all day)**

```
SELECT 
    sm.statistic_id,
    datetime(s.start_ts, 'unixepoch', 'localtime') as period_start,
    s.mean,
    s.min,
    s.max
FROM statistics s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.montry_temperature'
  AND DATE(datetime(s.start_ts, 'unixepoch', 'localtime')) = '2026-01-25'
ORDER BY s.start_ts ASC;
```

### **Calculate daily consumption from sum:**

```
SELECT 
    sm.statistic_id,
    DATE(datetime(s.start_ts, 'unixepoch', 'localtime')) as date,
    MAX(s.sum) - MIN(s.sum) as daily_total,
    sm.unit_of_measurement
FROM statistics s
JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.linky_east'
  AND s.sum IS NOT NULL
  AND DATE(datetime(s.start_ts, 'unixepoch', 'localtime')) = '2026-01-25'
GROUP BY DATE(datetime(s.start_ts, 'unixepoch', 'localtime'))
ORDER BY date DESC;
```

## **Tips for Using SQLite Web**

1. **Timestamps**: Home Assistant stores times as Unix timestamps (floating point). Use `datetime(timestamp, 'unixepoch', 'localtime')` to convert to readable dates.
2. **Entity relationships**: Always join `states` with `states_meta` to get the actual entity_id, and optionally with `state_attributes` for attributes.
3. **Performance**: For large databases, add `WHERE` clauses to limit time ranges, especially when querying states or events.
4. **JSON in attributes**: The `shared_attrs` field contains JSON data. In SQLite, you can parse it with `json_extract()` function.



## **Pattern Matching**

### Find all entities containing "temperature"

```
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature%'
ORDER BY sm.entity_id;
```

### Common pattern matching wildcards

- `%` = matches any sequence of characters (including zero characters)
- `_` = matches exactly one character

## **Pattern Matching Examples**

### Entities that START with "sensor.temperature"

```
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE 'sensor.temperature%'
ORDER BY sm.entity_id;
```

### Entities that END with "temperature"

```
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature'
ORDER BY sm.entity_id;
```

### Entities containing "temp" OR "temperature"

```
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temp%' 
   OR sm.entity_id LIKE '%temperature%'
ORDER BY sm.entity_id;
```

### Case-insensitive matching (SQLite default behavior)

```
-- These will match "Temperature", "TEMPERATURE", "temperature", etc.
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature%'
ORDER BY sm.entity_id;
```

### Match exact pattern with underscore (single character wildcard)

```
-- Matches "sensor.temp_1", "sensor.temp_2", etc.
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE 'sensor.temp_%'
ORDER BY sm.entity_id;
```

## **Get Latest States with Pattern Matching**

### Latest temperature sensor values

```
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

## **Multiple Pattern Conditions**

### All climate and weather sensors

```
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

```
-- All sensors containing "temperature" but not "battery"
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature%'
  AND sm.entity_id NOT LIKE '%battery%'
ORDER BY sm.entity_id;
```

## **Count Matches**

### How many temperature entities do you have?

```
SELECT COUNT(DISTINCT sm.entity_id) as temperature_sensor_count
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature%';
```
