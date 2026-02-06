# Statistics Table Fields: `created_ts` and `mean_weight`

## Overview

While most fields in Home Assistant's statistics tables are well documented, two fields remain somewhat mysterious: `created_ts` and `mean_weight`. This document provides detailed information about these fields based on research and code analysis.

---

## 1. The `created_ts` Field

### What It Is

`created_ts` is a **Unix timestamp** (float) that records **when the statistic record was created/written to the database** by Home Assistant.

### Key Characteristics

**Data Type:** `FLOAT` (Unix timestamp in seconds since epoch)

**Purpose:** Tracks when HA's statistics compilation process wrote this particular record

**Relationship to `start_ts`:**

- `start_ts`: The **beginning** of the time period the statistics represent
- `created_ts`: When the statistics **were calculated and written** to the database

### Practical Example

For **hourly long-term statistics**:

```text
start_ts:   1704970800  → 2024-01-11 12:00:00 (start of the hour being measured)
created_ts: 1704974400  → 2024-01-11 13:00:00 (when HA compiled and wrote the stats)
```

The statistics for the 12:00-13:00 period are typically written at or shortly after 13:00.

For **5-minute short-term statistics**:

```text
start_ts:   1704970800  → 2024-01-11 12:00:00
created_ts: 1704971100  → 2024-01-11 12:05:00
```

### Why This Matters

**Delayed Processing Detection:**

If `created_ts` is significantly later than `start_ts + period_duration`, it indicates:

- Home Assistant was restarted or offline
- Database performance issues
- Heavy system load delaying statistics compilation

**Manual Data Insertion:**
When manually inserting statistics (e.g., importing historical data), you must provide both timestamps:

```sql
INSERT INTO statistics 
(metadata_id, start_ts, created_ts, mean, min, max, state, sum)
VALUES 
(86, 1704970800, 1704974400, 22.5, 21.0, 24.0, NULL, NULL);
```

### Common Query Pattern

To see both timestamps in human-readable format:

```sql
-- sqlite version
SELECT 
    datetime(start_ts, 'unixepoch', 'localtime') as period_start,
    datetime(created_ts, 'unixepoch', 'localtime') as written_at,
    mean, min, max
FROM statistics 
WHERE metadata_id = 86
ORDER BY start_ts DESC;
```

```sql
-- mysql version
SELECT 
    FROM_UNIXTIME(start_ts) as period_start,
    FROM_UNIXTIME(created_ts) as written_at,
    mean, min, max
FROM statistics 
WHERE metadata_id = 86
ORDER BY start_ts DESC;
```

| period_start   | written_at     | mean        | min   | max   |
| -------------- | -------------- | ----------- | ----- | ----- |
| 2/5/2026 7:00  | 2/5/2026 8:00  | 144.3273889 | 142.2 | 146.1 |
| 2/5/2026 8:00  | 2/5/2026 9:00  | 143.6626811 | 141.6 | 146.1 |
| 2/5/2026 9:00  | 2/5/2026 10:00 | 144.4043766 | 141.5 | 146.7 |
| 2/5/2026 10:00 | 2/5/2026 11:00 | 146.109867  | 142.7 | 148.9 |
| 2/5/2026 11:00 | 2/5/2026 12:00 | 145.40353   | 142.2 | 148   |
| 2/5/2026 12:00 | 2/5/2026 13:00 | 143.6489361 | 142.2 | 145.6 |
| 2/5/2026 13:00 | 2/5/2026 14:00 | 142.8146935 | 141.2 | 144.6 |

### Deprecated Fields

Note that older versions had `created` and `start` fields (DATETIME format) which have been replaced by `created_ts` and `start_ts` (Unix timestamp format) for better performance.

---

## 2. The `mean_weight` Field

### What It Is

`mean_weight` is a **weight factor** used when calculating **circular mean values** for angular measurements like wind direction, where standard arithmetic averaging would be incorrect.

### The Problem with Angular Measurements

Consider wind direction readings:

- Reading 1: 350° (almost North)
- Reading 2: 10° (just past North)

**Arithmetic mean:** (350 + 10) / 2 = **180°** (South) ❌ WRONG!

**Correct circular mean:** **0°** (North) ✓ CORRECT!

This is why angular measurements need special handling.

### Key Characteristics

**Data Type:** `DOUBLE PRECISION` (floating point)

**Added:** Home Assistant 2025.4.x (recent addition to schema)

**Purpose:** Store weight factors for circular mean calculations

**When Used:** Only for entities with angular/directional measurements:

- Wind direction sensors (0-360°)
- Compass bearings
- Any circular/angular measurement

### How It Works

The `mean_weight` field stores a **normalized weight** that helps combine circular measurements correctly using **vector averaging**:

1. Each angular measurement is converted to **unit vectors**:
   - X component: `cos(angle)`
   - Y component: `sin(angle)`

2. These vectors are **weighted and averaged**

3. The result is converted **back to an angle**

The `mean_weight` helps track how many measurements contributed to each statistic period, allowing proper weighted averaging across time periods.

### Mean Type in statistics_meta

The `statistics_meta` table has a `mean_type` field with values:

- `0`: **No mean** (Counters)
- `1`: **Arithmetic mean** (default for normal sensors like temperature)
- `2`: **Circular mean** (for angular measurements like wind direction)

**Example from statistics_meta:**

```sql
SELECT statistic_id, unit_of_measurement, mean_type 
FROM statistics_meta 
WHERE statistic_id LIKE '%wind%bearing%';
```

Result:

```text
sensor.wind_bearing    °    1  (Circular mean)
```

### Schema Migration Issue

When the `mean_weight` field was added in HA 2025.4, some MySQL/MariaDB users encountered migration errors:

```text
ALTER TABLE statistics_short_term ADD mean_weight DOUBLE PRECISION
```

This was due to InnoDB engine limitations with certain table options. The issue has been addressed in subsequent releases.

### Practical Example

For a wind direction sensor over one hour:

**Individual readings (at 5-minute intervals):**

- 12:00: 350°
- 12:05: 355°
- 12:10: 0°
- 12:15: 5°
- 12:20: 10°
- 12:25: 8°
- 12:30: 2°
- 12:35: 358°
- 12:40: 0°
- 12:45: 3°
- 12:50: 7°
- 12:55: 5°

**Short-term statistics record (each 5-min period):**

```text
start_ts: 1704970800
mean: 1.2°  (circular mean of readings in this 5-min window)
mean_weight: 12.0  (12 individual measurements contributed)
```

**Long-term statistics (hourly aggregate):**

```text
start_ts: 1704970800
mean: 2.1°  (circular mean of all 12 short-term statistics)
mean_weight: 144.0  (total of all measurements: 12 periods × 12 readings each)
```

### When mean_weight is NULL

For non-angular sensors (temperature, humidity, power, etc.), `mean_weight` remains `NULL` because:

- They use arithmetic mean (mean_type = 0)
- No circular averaging needed
- Standard weighted average calculations apply

### Querying Circular Mean Statistics

**Find all sensors using circular mean:**

```sql
SELECT sm.statistic_id, sm.unit_of_measurement, sm.mean_type
FROM statistics_meta sm
WHERE sm.mean_type = 2;
```

**Get wind direction statistics with weights:**

```sql
SELECT 
    FROM_UNIXTIME(s.start_ts) as period,
    s.mean as avg_direction,
    s.mean_weight as measurement_count,
    s.min as min_direction,
    s.max as max_direction
FROM statistics s
JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.wind_bearing'
AND s.start_ts > UNIX_TIMESTAMP(NOW() - INTERVAL 24 HOUR)
ORDER BY s.start_ts DESC;
```

### Implementation References

The circular mean implementation can be found in Home Assistant's core:

- `homeassistant/components/sensor/recorder.py`
- Statistics compilation uses circular statistics when `mean_type = 2`
- Vector averaging with proper weight tracking

---

## Summary Table

| Field | Type | Purpose | When Populated | Special Notes |
|-------|------|---------|----------------|---------------|
| `start_ts` | FLOAT | Start of measurement period | Always | Marks the beginning of the time window |
| `created_ts` | FLOAT | When record was written | Always | Usually `start_ts + period_duration` or later |
| `mean` | FLOAT | Average value | For state_class: measurement | Arithmetic OR circular depending on mean_type |
| `mean_weight` | DOUBLE | Weight for circular averaging | Only when mean_type=1 | NULL for arithmetic mean sensors |

---

## Practical Use Cases

### 1. Detecting Statistics Processing Delays

```sql
SELECT 
    sm.statistic_id,
    FROM_UNIXTIME(s.start_ts) as period_start,
    FROM_UNIXTIME(s.created_ts) as written_at,
    (s.created_ts - s.start_ts) / 3600 as hours_delay
FROM statistics s
JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE (s.created_ts - s.start_ts) > 7200  -- More than 2 hours delay
ORDER BY hours_delay DESC
LIMIT 20;
```

### 2. Identifying Angular Sensors

```sql
SELECT 
    statistic_id,
    unit_of_measurement,
    CASE mean_type 
        WHEN 0 THEN 'Arithmetic'
        WHEN 1 THEN 'Circular'
        ELSE 'Unknown'
    END as mean_algorithm
FROM statistics_meta
WHERE has_mean = 1
ORDER BY mean_type DESC, statistic_id;
```

### 3. Validating Imported Historical Data

When importing historical statistics, ensure:

- `created_ts` is reasonable (not in the future)
- `created_ts` >= `start_ts`
- For circular mean sensors, include `mean_weight` if available

---

## Troubleshooting

### Issue: Statistics showing wrong averages for wind direction

**Cause:** Sensor changed from arithmetic to circular mean after data was already collected

**Solution:**

1. Check if entity should have circular mean: `SELECT * FROM statistics_meta WHERE statistic_id = 'sensor.your_wind_sensor'`
2. If `mean_type = 1` but should be `2`, the integration needs to be updated
3. Historical data may need recalculation or manual correction

### Issue: mean_weight column missing (pre-2025.4)

**Cause:** Running older Home Assistant version

**Solution:** Upgrade to HA 2025.4 or later. The schema migration will add the column automatically.

### Issue: Large delay between start_ts and created_ts

**Cause:** Home Assistant was offline, or statistics compilation was delayed

**Impact:**

- Statistics are still valid
- Indicates past system issues
- May affect real-time dashboard updates

**Solution:** Check HA logs from that time period for errors or restart events

---

## Conclusion

Both `created_ts` and `mean_weight` serve important but specialized purposes:

- **`created_ts`**: Provides audit trail for when statistics were compiled, useful for debugging processing delays and validating manual data imports

- **`mean_weight`**: Enables proper statistical aggregation of angular measurements, solving the circular mean problem for wind direction and similar sensors

Understanding these fields helps with:

- Advanced database queries
- Manual statistics manipulation
- Troubleshooting statistics issues
- Properly importing historical data
- Understanding statistics compilation timing

---

## References

1. Home Assistant Data Science Portal: <https://data.home-assistant.io/docs/statistics/>
2. GitHub Issue #142249: Mean type changes for circular sensors
3. GitHub Issue #142408: mean_weight schema migration issues
4. Home Assistant Database Schema: <https://www.home-assistant.io/docs/backend/database/>
