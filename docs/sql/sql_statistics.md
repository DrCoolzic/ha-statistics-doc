
# Useful SQL Queries for Accessing Statistics Information

## Retrieve measurement statistics between specific dates

```sql
-- MySQL version
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

```sqlite
-- SQLite version
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

## Compute average/min/max from measurement statistics for 7 days

```sql
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

## Retrieve counter statistics between specific dates  -- SQLite version

```sql
-- Retrieve stat and compute delta (growth)
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

## Get All Statistics for a day (all day) for a specific entity

```sql
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

## Calculate daily consumption from sum

```sql
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

## Calculate Hourly Consumption (Energy Used Per Hour)

```sql
-- This calculates the actual energy consumed during each hour for the past 7 day:
WITH hourly_data AS (
    SELECT
        strftime('%H', datetime(s.start_ts, 'unixepoch', 'localtime')) as hour_of_day,
        datetime(s.start_ts, 'unixepoch', 'localtime') as timestamp,
        s.sum,
        LAG(s.sum) OVER (ORDER BY s.start_ts) as prev_sum
    FROM statistics s
    JOIN statistics_meta sm ON s.metadata_id = sm.id
    WHERE sm.statistic_id = 'sensor.linky_east'
      AND s.start_ts >= strftime('%s', 'now', '-7 days')
)
SELECT
    hour_of_day,
    ROUND(AVG(sum - COALESCE(prev_sum, sum)), 2) as avg_consumption_per_period,
    COUNT(*) as sample_count
FROM hourly_data
WHERE prev_sum IS NOT NULL
GROUP BY hour_of_day
ORDER BY hour_of_day;
```

## Queries statistics to find entities: matching state / deleted from state / external

### Count each category

```sql
SELECT 
    COUNT(DISTINCT sm_stats.statistic_id) as total_statistics,
    COUNT(DISTINCT CASE 
        WHEN sm_states.entity_id IS NOT NULL THEN sm_stats.statistic_id 
    END) as matching_entities,
    COUNT(DISTINCT CASE 
        WHEN sm_states.entity_id IS NULL 
        AND sm_stats.statistic_id LIKE '%.%' 
        THEN sm_stats.statistic_id 
    END) as deleted_entities,
    COUNT(DISTINCT CASE 
        WHEN sm_states.entity_id IS NULL 
        AND sm_stats.statistic_id LIKE '%:%' 
        THEN sm_stats.statistic_id 
    END) as external_entities
FROM statistics_meta sm_stats
LEFT JOIN states_meta sm_states ON sm_stats.statistic_id = sm_states.entity_id;
```

### List entities in categories active/external/deleted

```sql
SELECT 
    CASE 
        WHEN sm_states.entity_id IS NOT NULL THEN 'Active'
        WHEN sm_stats.statistic_id LIKE '%:%' THEN 'External'
        WHEN sm_stats.statistic_id LIKE '%.%' THEN 'Deleted'
        ELSE 'Other'
    END as category,
    sm_stats.statistic_id,
    sm_stats.source,
    sm_stats.unit_of_measurement,
    sm_stats.has_sum,
    CASE sm_stats.has_sum 
        WHEN 1 THEN 'Counter/Total' 
        ELSE 'Measurement' 
    END as type
FROM statistics_meta sm_stats
LEFT JOIN states_meta sm_states ON sm_stats.statistic_id = sm_states.entity_id
ORDER BY category, sm_stats.statistic_id;
```

### List ONLY Deleted Entities

```sql
SELECT 
    sm_stats.statistic_id,
    sm_stats.source,
    sm_stats.unit_of_measurement,
    CASE sm_stats.has_sum 
        WHEN 1 THEN 'Counter/Total' 
        ELSE 'Measurement' 
    END as type,
    COUNT(s.id) as statistics_records
FROM statistics_meta sm_stats
LEFT JOIN states_meta sm_states ON sm_stats.statistic_id = sm_states.entity_id
LEFT JOIN statistics s ON sm_stats.id = s.metadata_id
WHERE sm_states.entity_id IS NULL 
  AND sm_stats.statistic_id LIKE '%.%'  -- Has dot notation (internal entity format)
GROUP BY sm_stats.statistic_id, sm_stats.source, sm_stats.unit_of_measurement, sm_stats.has_sum
ORDER BY statistics_records DESC;
```

### List ONLY External Statistics

```sql
SELECT 
    sm_stats.statistic_id,
    sm_stats.source,
    sm_stats.unit_of_measurement,
    CASE sm_stats.has_sum 
        WHEN 1 THEN 'Counter/Total' 
        ELSE 'Measurement' 
    END as type,
    COUNT(s.id) as statistics_records,
    datetime(MIN(s.start_ts), 'unixepoch', 'localtime') as first_record,
    datetime(MAX(s.start_ts), 'unixepoch', 'localtime') as last_record
FROM statistics_meta sm_stats
LEFT JOIN states_meta sm_states ON sm_stats.statistic_id = sm_states.entity_id
LEFT JOIN statistics s ON sm_stats.id = s.metadata_id
WHERE sm_states.entity_id IS NULL 
  AND sm_stats.statistic_id LIKE '%:%'  -- Has colon notation (external format)
GROUP BY sm_stats.statistic_id, sm_stats.source, sm_stats.unit_of_measurement, sm_stats.has_sum
ORDER BY sm_stats.statistic_id;
```

### Comprehensive Summary with All Details

```sql
WITH category_stats AS (
    SELECT 
        sm_stats.statistic_id,
        sm_stats.source,
        sm_stats.unit_of_measurement,
        sm_stats.has_sum,
        CASE 
            WHEN sm_states.entity_id IS NOT NULL THEN 'Active'
            WHEN sm_stats.statistic_id LIKE '%:%' THEN 'External'
            WHEN sm_stats.statistic_id LIKE '%.%' THEN 'Deleted'
            ELSE 'Other'
        END as category,
        COUNT(s.id) as record_count
    FROM statistics_meta sm_stats
    LEFT JOIN states_meta sm_states ON sm_stats.statistic_id = sm_states.entity_id
    LEFT JOIN statistics s ON sm_stats.id = s.metadata_id
    GROUP BY sm_stats.statistic_id, sm_stats.source, sm_stats.unit_of_measurement, 
             sm_stats.has_sum, sm_states.entity_id
)
SELECT 
    category,
    COUNT(*) as entity_count,
    SUM(record_count) as total_records
FROM category_stats
GROUP BY category
ORDER BY category;
```

### Find Entities That Might Be Renamed

```sql
-- Sometimes entities get renamed (e.g., sensor.temp → sensor.temperature). This query finds potential matches:
SELECT 
    sm_stats.statistic_id as deleted_statistic,
    sm_states.entity_id as possible_match,
    datetime(MAX(s.start_ts), 'unixepoch', 'localtime') as last_stats_record
FROM statistics_meta sm_stats
LEFT JOIN states_meta sm_states ON SUBSTR(sm_stats.statistic_id, 1, INSTR(sm_stats.statistic_id, '.') + 3) = 
                                    SUBSTR(sm_states.entity_id, 1, INSTR(sm_states.entity_id, '.') + 3)
LEFT JOIN statistics s ON sm_stats.id = s.metadata_id
WHERE NOT EXISTS (
    SELECT 1 FROM states_meta WHERE entity_id = sm_stats.statistic_id
)
AND sm_stats.statistic_id LIKE '%.%'
AND sm_stats.statistic_id != sm_states.entity_id
GROUP BY sm_stats.statistic_id, sm_states.entity_id
ORDER BY sm_stats.statistic_id;
```

### Export statistics inventory

```sql
SELECT 
    sm_stats.statistic_id,
    sm_stats.unit_of_measurement,
    sm_stats.source,
    CASE 
        WHEN sm_states.entity_id IS NOT NULL THEN 'Internal'
        WHEN sm_stats.statistic_id LIKE '%:%' THEN 'External'
        WHEN sm_stats.statistic_id LIKE '%.%' THEN 'Deleted'
        ELSE 'Other'
    END as category,
    CASE sm_stats.has_sum 
        WHEN 1 THEN 'Counter' 
        ELSE 'Measurement' 
    END as type,
    COUNT(s.id) as sample_count,
    datetime(MIN(s.start_ts), 'unixepoch', 'localtime') as first_seen,
    datetime(MAX(s.start_ts), 'unixepoch', 'localtime') as last_seen,
    ROUND(JULIANDAY(MAX(s.start_ts), 'unixepoch') - JULIANDAY(MIN(s.start_ts), 'unixepoch'), 1) as days_span
FROM statistics_meta sm_stats
LEFT JOIN states_meta sm_states ON sm_stats.statistic_id = sm_states.entity_id
LEFT JOIN statistics s ON sm_stats.id = s.metadata_id
GROUP BY sm_stats.statistic_id, sm_stats.source, sm_stats.unit_of_measurement, sm_stats.has_sum, sm_states.entity_id
ORDER BY category, sm_stats.statistic_id;
```
