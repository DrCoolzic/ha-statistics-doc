# Quick Reference Guide

## State Class Cheat Sheet

| Data Type | State Class | Fields Tracked | Example |
|-----------|-------------|----------------|---------|
| Current measurement | `measurement` | mean, min, max | Temperature: 23.5°C |
| Angular measurement | `measurement_angle` | circular mean, min, max | Wind: 350° |
| Cumulative (increases only) | `total_increasing` | state, sum | Energy: 1234 kWh |
| Cumulative (bidirectional) | `total` | state, sum | Net energy: +50 kWh |

## Essential Fields

### statistics_meta

- `statistic_id`: Entity identifier
- `has_sum`: 1 for counters, 0 for measurements
- `mean_type`: 0=none, 1=arithmetic, 2=circular

### statistics / statistics_short_term

- `start_ts`: Period start (Unix timestamp)
- `created_ts`: When written to DB
- `mean`, `min`, `max`: For measurements
- `state`, `sum`: For counters

## Common SQL Snippets

### Find all entities generating statistics

```sql
SELECT statistic_id, unit_of_measurement, has_sum, mean_type
FROM statistics_meta
ORDER BY statistic_id;
```

### Get hourly energy consumption

```sql
SELECT 
  datetime(start_ts, 'unixepoch', 'localtime') as hour,
  sum - LAG(sum) OVER (ORDER BY start_ts) as consumption
FROM statistics
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy')
ORDER BY start_ts DESC LIMIT 24;
```
