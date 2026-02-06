# Finding & Fixing Statistics errors

Over time, errors may appear in the statistical database for various reasons. We will first describe the different types of errors and then we will examine how some of them can be corrected.

## Errors in the statistics database

- missing  statistics: sensor/integration not delivering data
  - for measurement "hole" in the history graph
  - for counters big jump in bar graph
- wrong statistics: sensor/integration delivering wrong data (glitches, spikes, etc.)
  - for measurement just one invalid value
  - for counters big jump in bar graph in one direction followed by a big jump in the other direction (should generate a reset?)
- statistics on deleted entities
- unit of measurement changed
- renamed entities




# Part 5: Finding & Fixing Statistics Errors

Over time, errors may appear in the statistical database for various reasons. This part describes the different types of errors, how to identify them, and methods to correct them.

---

## 5.1 Types of Statistics Errors

Understanding the error type is the first step toward fixing it. Each error manifests differently in the UI and database.

---

### 5.1.1 Missing Statistics (Data Gaps)

**Description:**  
Periods where no statistics were recorded despite the entity existing and presumably having data.

**Causes:**
- Sensor/integration temporarily not delivering data (device offline, network issue)
- Entity was excluded from recorder during that period
- Statistics generation was disabled (`state_class` was temporarily removed)
- Home Assistant was not running
- Database write errors

**Manifestation:**

**For measurement entities:**
- Visible gaps/holes in history graphs
- Flat lines where interpolation fails
- Missing data points in min/max/mean charts

**For counter entities:**
- Missing bars in bar chart (energy dashboard)
- Discontinuity in cumulative sum
- Appears as zero consumption for that period

**Example:**
```
Temperature History:
12:00 → 21.5°C
13:00 → 22.0°C
14:00 → [MISSING]  ← No data recorded
15:00 → [MISSING]  ← No data recorded
16:00 → 23.5°C
```

**Database signature:**
```sql
-- Check for gaps in statistics
SELECT 
  datetime(start_ts, 'unixepoch', 'localtime') as period,
  mean,
  CASE 
    WHEN start_ts - LAG(start_ts) OVER (ORDER BY start_ts) > 3600 
    THEN 'GAP DETECTED'
    ELSE 'OK'
  END as gap_check
FROM statistics
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.temperature')
ORDER BY start_ts DESC
LIMIT 50;
```

---

### 5.1.2 Invalid Data / Spikes

**Description:**  
Statistics contain obviously wrong values due to sensor glitches, measurement errors, or data corruption.

**Causes:**
- Sensor hardware malfunction (reading errors)
- Communication interference (corrupt packets)
- Integration bugs (incorrect parsing)
- Sensor calibration issues
- Power fluctuations affecting readings
- No validation in template sensors

**Manifestation:**

**For measurement entities:**
- Extreme outliers in min/max values
- Impossible values (e.g., -273.15°C temperature, 150% humidity)
- Single extreme spikes followed by return to normal
- Affects mean calculation for that period

**For counter entities:**
- Massive positive spike followed by negative spike (or vice versa)
- Sum jumps unrealistically high then drops back
- Can trigger false counter reset detection
- Creates artificial consumption peaks in energy dashboard

**Example:**
```
Temperature readings:
12:00 → mean: 21.5°C, min: 21.2°C, max: 21.8°C  [NORMAL]
13:00 → mean: 45.2°C, min: 21.5°C, max: 89.7°C  [SPIKE ERROR]
14:00 → mean: 21.8°C, min: 21.6°C, max: 22.0°C  [BACK TO NORMAL]
```

**Database signature:**
```sql
-- Find outliers (values > 3 standard deviations from mean)
WITH stats AS (
  SELECT 
    AVG(mean) as avg_mean,
    AVG(mean * mean) - AVG(mean) * AVG(mean) as variance
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.temperature')
)
SELECT 
  datetime(start_ts, 'unixepoch', 'localtime') as period,
  mean,
  min,
  max,
  CASE 
    WHEN ABS(mean - (SELECT avg_mean FROM stats)) > 3 * SQRT((SELECT variance FROM stats))
    THEN '⚠️ OUTLIER'
    ELSE 'OK'
  END as outlier_check
FROM statistics
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.temperature')
ORDER BY start_ts DESC;
```

---

### 5.1.3 Statistics on Deleted Entities

**Description:**  
Statistics remain in the database for entities that no longer exist in Home Assistant.

**Causes:**
- Entity was deleted or removed from configuration
- Integration was uninstalled
- Device was removed
- Entity ID was changed without migration
- Statistics were not purged when entity was deleted

**Manifestation:**
- Statistics shown in Developer Tools → Statistics for non-existent entities
- Orphaned `statistic_id` entries in `statistics_meta`
- Wasted database space
- Confusing in energy dashboard or history graphs
- Entity appears in statistics but not in entity list

**Example:**
```
statistics_meta table:
| statistic_id                  | source   | unit | has_sum |
|-------------------------------|----------|------|---------|
| sensor.old_temperature        | recorder | °C   | 0       | ← Entity deleted
| sensor.removed_power_meter    | recorder | W    | 0       | ← Integration removed
| sensor.current_temperature    | recorder | °C   | 0       | ← Still exists ✓
```

**Database signature:**
```sql
-- Find statistics for entities that no longer exist
-- (Requires manual verification against current entities)
SELECT 
  sm.statistic_id,
  sm.source,
  COUNT(s.id) as record_count,
  datetime(MIN(s.start_ts), 'unixepoch', 'localtime') as first_record,
  datetime(MAX(s.start_ts), 'unixepoch', 'localtime') as last_record
FROM statistics_meta sm
LEFT JOIN statistics s ON sm.id = s.metadata_id
GROUP BY sm.statistic_id
ORDER BY last_record DESC;
```

---

### 5.1.4 Unit of Measurement Changed

**Description:**  
The sensor's unit of measurement changed, creating a new statistics series and discontinuity in data.

**Causes:**
- Sensor configuration was changed (e.g., Wh → kWh)
- Integration updated with different default units
- Manual reconfiguration
- Device firmware change
- Template sensor modified

**Manifestation:**
- Two separate entries in `statistics_meta` for what should be one sensor
- Different `statistic_id` entries (often with suffix like `_2`, `_3`)
- Graphs show discontinuity at the change point
- Energy dashboard may not recognize the new series
- Historical data appears "lost" (actually in different series)

**Example:**
```
statistics_meta table:
| id | statistic_id              | unit_of_measurement | has_sum |
|----|---------------------------|---------------------|---------|
| 42 | sensor.power_consumption  | Wh                  | 1       | ← Old (stopped 2025-12-01)
| 89 | sensor.power_consumption  | kWh                 | 1       | ← New (started 2025-12-01)
```

**Visual effect:**
```
Energy graph shows:
Jan-Nov 2025: [███████████████] 15000 Wh total
Dec 2025-Jan 2026: [No data shown] ← Actually exists but in different series
```

**Database signature:**
```sql
-- Find duplicate statistic_id with different units
SELECT 
  statistic_id,
  unit_of_measurement,
  COUNT(*) as series_count,
  GROUP_CONCAT(id) as metadata_ids
FROM statistics_meta
GROUP BY statistic_id
HAVING COUNT(*) > 1
ORDER BY statistic_id;
```

---

### 5.1.5 Renamed Entities

**Description:**  
Entity was renamed, but statistics remain under the old `entity_id`, causing apparent data loss.

**Causes:**
- Entity renamed via UI (Settings → Entities)
- Entity ID changed in configuration.yaml
- Integration reorganized entity IDs
- Device renamed causing entity_id change

**Manifestation:**
- Statistics exist for old entity_id but not new one
- Historical data appears "missing" for renamed entity
- Two entries appear: one with history (old name), one without (new name)
- Energy dashboard loses tracking continuity
- Automations referencing old statistics fail

**Example:**
```
Old: sensor.living_room_temperature
New: sensor.lounge_temperature

statistics_meta shows:
| statistic_id                     | Last record       |
|----------------------------------|-------------------|
| sensor.living_room_temperature   | 2025-12-15        | ← All history here
| sensor.lounge_temperature        | 2025-12-16 →      | ← New data here
```

**Database signature:**
```sql
-- Find statistics that might be renamed (similar names, one stopped, one started)
SELECT 
  sm1.statistic_id as old_name,
  MAX(s1.start_ts) as old_last_record,
  sm2.statistic_id as possibly_new_name,
  MIN(s2.start_ts) as new_first_record,
  ABS(MAX(s1.start_ts) - MIN(s2.start_ts)) as time_gap_seconds
FROM statistics_meta sm1
JOIN statistics s1 ON sm1.id = s1.metadata_id
JOIN statistics_meta sm2 ON sm1.unit_of_measurement = sm2.unit_of_measurement
  AND sm1.has_sum = sm2.has_sum
  AND sm1.statistic_id != sm2.statistic_id
JOIN statistics s2 ON sm2.id = s2.metadata_id
WHERE time_gap_seconds < 86400  -- Within 24 hours
GROUP BY sm1.statistic_id, sm2.statistic_id
ORDER BY time_gap_seconds;
```

---

### 5.1.6 Duplicate Statistics

**Description:**  
Multiple statistics records exist for the same entity and time period, causing data integrity issues.

**Causes:**
- Database corruption
- Import errors when migrating databases
- Manual SQL modifications gone wrong
- Statistics repair tool malfunction
- Concurrent write conflicts

**Manifestation:**
- Multiple records with identical `metadata_id` and `start_ts`
- Inconsistent values shown in different UI views
- Errors in Developer Tools → Statistics validation
- Warnings in Home Assistant logs
- Incorrect aggregations in long-term statistics

**Example:**
```sql
SELECT * FROM statistics 
WHERE metadata_id = 42 AND start_ts = 1735660800;

| id    | metadata_id | start_ts   | mean  | sum   |
|-------|-------------|------------|-------|-------|
| 10001 | 42          | 1735660800 | 23.5  | NULL  | ← Duplicate!
| 10023 | 42          | 1735660800 | 23.7  | NULL  | ← Duplicate!
```

**Database signature:**
```sql
-- Find duplicate statistics
SELECT 
  metadata_id,
  start_ts,
  datetime(start_ts, 'unixepoch', 'localtime') as period,
  COUNT(*) as duplicate_count,
  GROUP_CONCAT(id) as record_ids
FROM statistics
GROUP BY metadata_id, start_ts
HAVING COUNT(*) > 1
ORDER BY start_ts DESC;
```

---

### 5.1.7 State Class Changed

**Description:**  
The `state_class` attribute was changed (e.g., `measurement` → `total_increasing`), creating incompatible statistics.

**Causes:**
- Configuration error or experimentation
- Integration update changed default state class
- User misunderstanding of state_class purpose
- Template sensor reconfiguration

**Manifestation:**
- New `statistic_id` may be created with suffix
- Existing statistics may show validation warnings
- Incorrect statistics type for entity behavior
- Energy dashboard may reject the sensor
- Graphs show wrong visualization type

**Example:**
```
Before: state_class: measurement  → tracks mean/min/max
After:  state_class: total_increasing → tracks sum

Result:
- Old statistics show mean values (e.g., 2.5 kW)
- New statistics show sum values (e.g., 150 kWh)
- Incompatible for merging or comparison
```

**Database signature:**
```sql
-- Detect potential state_class changes
-- (Look for metadata_id with both has_sum=0 and has_sum=1 for similar statistic_id)
SELECT 
  sm1.statistic_id,
  sm1.has_sum as type1_has_sum,
  sm1.mean_type as type1_mean_type,
  sm2.statistic_id as similar_id,
  sm2.has_sum as type2_has_sum,
  sm2.mean_type as type2_mean_type
FROM statistics_meta sm1
JOIN statistics_meta sm2 
  ON sm1.statistic_id LIKE sm2.statistic_id || '%'
  OR sm2.statistic_id LIKE sm1.statistic_id || '%'
WHERE sm1.has_sum != sm2.has_sum
  AND sm1.id != sm2.id;
```

---

### 5.1.8 Counter Reset Not Detected

**Description:**  
A `total_increasing` counter reset to zero, but the statistics system didn't detect it, resulting in negative or missing consumption data.

**Causes:**
- Reset was too small (< 10% threshold)
- Counter decremented instead of resetting (hardware issue)
- Statistics compiler wasn't running during reset
- Database wasn't updated with `last_reset` timestamp
- Sensor temporarily reported unavailable during reset

**Manifestation:**
- Negative hourly consumption values in energy dashboard
- Sum stops increasing or shows incorrect totals
- Bar chart shows no consumption when there should be
- State value is lower than previous, but sum didn't adjust

**Example:**
```
Counter readings:
10:00 → state: 1250 kWh, sum: 1250 kWh
11:00 → state: 1255 kWh, sum: 1255 kWh (+5 kWh consumption) ✓
12:00 → state: 5 kWh,    sum: 1255 kWh (reset not detected!)
13:00 → state: 8 kWh,    sum: 1258 kWh (+3 kWh consumption) ✓

Expected at 12:00: sum should handle reset gracefully
Actual: sum froze, hourly consumption = 0
```

**Database signature:**
```sql
-- Find potential missed resets
SELECT 
  datetime(start_ts, 'unixepoch', 'localtime') as period,
  state,
  LAG(state) OVER (ORDER BY start_ts) as previous_state,
  sum,
  LAG(sum) OVER (ORDER BY start_ts) as previous_sum,
  CASE 
    WHEN state < LAG(state) OVER (ORDER BY start_ts) * 0.9 
         AND sum = LAG(sum) OVER (ORDER BY start_ts)
    THEN '⚠️ MISSED RESET'
    ELSE 'OK'
  END as reset_check
FROM statistics
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
ORDER BY start_ts DESC
LIMIT 50;
```

---

### 5.1.9 Wrong Mean Type (Circular vs Arithmetic)

**Description:**  
Non-angular data is being processed with circular mean, or angular data with arithmetic mean.

**Causes:**
- Incorrect `device_class` configuration
- Template sensor without proper device_class
- Integration bug assigning wrong device_class
- Manual database modification error

**Manifestation:**
- Angular sensors show impossible mean values
  - Wind direction mean of 520° (should be 0-360°)
  - Compass heading with negative values
- Non-angular sensors averaged incorrectly
  - Temperature treated as circular (rare but possible configuration error)

**Example:**
```
Wind Direction Sensor with mean_type=1 (arithmetic) - WRONG:
0° + 350° + 340° = 690° / 3 = 230°  ← WRONG! (should be ~350°)

Wind Direction Sensor with mean_type=2 (circular) - CORRECT:
0° + 350° + 340° → vectors → 350°  ← CORRECT!
```

**Database signature:**
```sql
-- Check mean_type matches device_class expectations
SELECT 
  sm.statistic_id,
  sm.mean_type,
  CASE sm.mean_type
    WHEN 0 THEN 'None'
    WHEN 1 THEN 'Arithmetic'
    WHEN 2 THEN 'Circular'
  END as mean_type_name,
  -- Check if statistic_id suggests angular data
  CASE 
    WHEN (sm.statistic_id LIKE '%direction%' 
          OR sm.statistic_id LIKE '%bearing%'
          OR sm.statistic_id LIKE '%heading%'
          OR sm.statistic_id LIKE '%azimuth%')
         AND sm.mean_type != 2 
    THEN '⚠️ Should be circular'
    WHEN sm.mean_type = 2 
         AND sm.statistic_id NOT LIKE '%direction%'
         AND sm.statistic_id NOT LIKE '%bearing%'
    THEN '⚠️ Should NOT be circular'
    ELSE 'OK'
  END as validation
FROM statistics_meta sm
WHERE sm.mean_type IN (1, 2);
```

---

### 5.1.10 Negative Values in Total_Increasing

**Description:**  
A `total_increasing` counter shows negative state or sum values, which violates the monotonic increase constraint.

**Causes:**
- Sensor returned negative value due to hardware error
- Template calculation error (e.g., subtraction instead of addition)
- Database corruption
- Manual statistics injection error
- Counter rollover with incorrect handling

**Manifestation:**
- Validation errors in Developer Tools → Statistics
- Energy dashboard shows negative consumption
- Bar charts with negative bars
- Warning messages in Home Assistant logs
- Impossible physical values (negative total energy consumed)

**Example:**
```
statistics table:
| start_ts   | state  | sum    | Issue                    |
|------------|--------|--------|--------------------------|
| 1735574400 | 1250.5 | 1250.5 | OK                       |
| 1735578000 | -5.2   | 1245.3 | ⚠️ Negative state value! |
| 1735581600 | 8.7    | 1254.0 | Recovered                |
```

**Database signature:**
```sql
-- Find negative values in total_increasing sensors
SELECT 
  sm.statistic_id,
  datetime(s.start_ts, 'unixepoch', 'localtime') as period,
  s.state,
  s.sum,
  '⚠️ NEGATIVE VALUE' as issue
FROM statistics s
JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.has_sum = 1  -- Counter type
  AND (s.state < 0 OR s.sum < 0)
ORDER BY s.start_ts DESC;
```

---

### 5.1.11 Large Unexpected Sum Jumps

**Description:**  
The `sum` field shows unrealistic jumps between periods that don't match the `state` values or expected consumption patterns.

**Causes:**
- Integration bug calculating sum incorrectly
- Counter reset handled incorrectly (added instead of continuing)
- Manual statistics import error
- Data corruption during database migration
- Sensor sent burst of accumulated data

**Manifestation:**
- Energy dashboard shows impossible consumption spikes
- Single hour shows years worth of consumption
- Sum increases by 1000x normal amount
- May appear as single tall bar in bar chart
- Following periods return to normal rates

**Example:**
```
Hourly consumption pattern:
10:00-11:00 → +2.5 kWh  [NORMAL]
11:00-12:00 → +2.8 kWh  [NORMAL]
12:00-13:00 → +2500 kWh [ERROR! - Should be ~2.5 kWh]
13:00-14:00 → +2.6 kWh  [NORMAL]
```

**Database signature:**
```sql
-- Find abnormal sum increases (>10x average)
WITH consumption AS (
  SELECT 
    metadata_id,
    start_ts,
    sum,
    sum - LAG(sum) OVER (ORDER BY start_ts) as hourly_consumption,
    AVG(sum - LAG(sum) OVER (ORDER BY start_ts)) OVER (
      ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING
    ) as avg_24h_consumption
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
)
SELECT 
  datetime(start_ts, 'unixepoch', 'localtime') as period,
  hourly_consumption,
  avg_24h_consumption,
  ROUND(hourly_consumption / avg_24h_consumption, 1) as multiplier,
  CASE 
    WHEN hourly_consumption > avg_24h_consumption * 10 
    THEN '⚠️ ABNORMAL SPIKE'
    ELSE 'OK'
  END as status
FROM consumption
WHERE hourly_consumption IS NOT NULL
  AND avg_24h_consumption > 0
ORDER BY start_ts DESC
LIMIT 100;
```

---

### 5.1.12 Orphaned Statistics Metadata

**Description:**  
Entries in `statistics_meta` table have no corresponding records in `statistics` or `statistics_short_term` tables.

**Causes:**
- Statistics were manually deleted but metadata wasn't
- Purge operation incomplete or interrupted
- Entity created but never generated statistics
- Database cleanup tools only cleaned data tables
- Statistics generation started but immediately failed

**Manifestation:**
- Metadata entries with zero statistics records
- Wasted database space (minimal but clutters queries)
- Confusion when querying metadata
- Gaps between expected and actual statistics count

**Example:**
```sql
statistics_meta entry exists:
| id | statistic_id              | unit | has_sum |
|----|---------------------------|------|---------|
| 99 | sensor.phantom_sensor     | kWh  | 1       |

But querying statistics:
SELECT COUNT(*) FROM statistics WHERE metadata_id = 99;
Result: 0  ← No statistics ever recorded!
```

**Database signature:**
```sql
-- Find orphaned metadata
SELECT 
  sm.id,
  sm.statistic_id,
  sm.source,
  sm.unit_of_measurement,
  COALESCE(s_count.count, 0) as long_term_count,
  COALESCE(ss_count.count, 0) as short_term_count,
  CASE 
    WHEN COALESCE(s_count.count, 0) = 0 
         AND COALESCE(ss_count.count, 0) = 0 
    THEN '⚠️ ORPHANED'
    ELSE 'OK'
  END as status
FROM statistics_meta sm
LEFT JOIN (
  SELECT metadata_id, COUNT(*) as count 
  FROM statistics 
  GROUP BY metadata_id
) s_count ON sm.id = s_count.metadata_id
LEFT JOIN (
  SELECT metadata_id, COUNT(*) as count 
  FROM statistics_short_term 
  GROUP BY metadata_id
) ss_count ON sm.id = ss_count.metadata_id
WHERE COALESCE(s_count.count, 0) = 0 
  AND COALESCE(ss_count.count, 0) = 0;
```

---

### 5.1.13 Mismatched Has_Sum and Mean_Type

**Description:**  
The `has_sum` and `mean_type` fields in `statistics_meta` have invalid combinations that violate statistics logic.

**Causes:**
- Database corruption
- Manual SQL modification error
- Statistics repair tool bug
- Migration error from older HA versions

**Manifestation:**
- Validation errors in Developer Tools
- Statistics compiler may skip these entities
- Queries return unexpected results
- Possible crashes in statistics-related UI

**Valid combinations:**
```
has_sum=0, mean_type=1  → Measurement (arithmetic)
has_sum=0, mean_type=2  → Measurement (circular)
has_sum=1, mean_type=0  → Counter (no mean)
```

**Invalid combinations:**
```
has_sum=1, mean_type=1  ❌ Counter shouldn't have mean
has_sum=1, mean_type=2  ❌ Counter shouldn't have circular mean
has_sum=0, mean_type=0  ❌ Measurement should have mean type
```

**Database signature:**
```sql
-- Find invalid has_sum / mean_type combinations
SELECT 
  statistic_id,
  has_sum,
  mean_type,
  CASE 
    WHEN has_sum = 1 AND mean_type != 0 
    THEN '❌ Counter should have mean_type=0'
    WHEN has_sum = 0 AND mean_type = 0 
    THEN '❌ Measurement should have mean_type=1 or 2'
    WHEN has_sum = 0 AND mean_type NOT IN (1, 2)
    THEN '❌ Invalid mean_type value'
    ELSE '✓ Valid'
  END as validation
FROM statistics_meta
WHERE NOT (
  (has_sum = 0 AND mean_type IN (1, 2)) OR
  (has_sum = 1 AND mean_type = 0)
);
```

---

## 5.2 Detecting Errors

### Using Developer Tools

**Settings → System → Repairs**
- Automatic detection of some issues
- One-click fixes for certain problems

**Developer Tools → Statistics**
- Shows all entities generating statistics
- Validation warnings highlighted
- "Fix issue" button for supported problems

### Using Database Queries

See the SQL queries provided in each error section above to detect specific issues.

### Monitoring Logs

Check `home-assistant.log` for warnings:
```
WARNING (Recorder) [homeassistant.components.recorder.statistics] 
  Statistics for sensor.power_meter has a new unit kWh (old unit was Wh)
  
WARNING (Recorder) [homeassistant.components.recorder.statistics]
  Detected duplicates for statistic_id sensor.energy_total
```

---

## 5.3 Fixing Statistics Errors

*(This section will cover solutions - would you like me to develop this section now with specific fixes for each error type?)*

### General Approaches
- Using Developer Tools → Statistics repair
- SQL UPDATE/DELETE commands
- Statistics export, fix, and re-import
- Entity renaming and metadata migration
- Manual sum adjustment

### When to Fix vs. When to Start Fresh
- Minor data gaps: Usually leave as-is
- Duplicate entries: Must fix (causes DB corruption)
- Unit changes: Migrate if possible
- Deleted entities: Clean up to save space
- Renamed entities: Always migrate to preserve history

---

## 5.4 Preventing Errors

### Best Practices
1. **Validate before deploying**
   - Test sensor configuration in developer template tool
   - Check `state_class` matches data type
   - Verify units before adding statistics

2. **Use availability templates**
   - Filter out 'unavailable' and 'unknown' states
   - Validate numeric values
   - Prevent glitch propagation

3. **Plan changes carefully**
   - Don't change units mid-stream
   - Rename entities via statistics migration tools
   - Test state_class changes on non-production data

4. **Regular monitoring**
   - Check Developer Tools → Statistics weekly
   - Review Settings → System → Repairs
   - Monitor log files for warnings

5. **Backup before modifications**
   - Always backup `home-assistant_v2.db` before direct SQL
   - Export critical statistics before migration
   - Test fixes on database copy first

---

**Previous** - [Part 4: Best Practices and Troubleshooting](part4_practices_troubleshooting.md)

---

This is comprehensive but probably needs the "5.3 Fixing Statistics Errors" section fully developed with specific solutions. Would you like me to:

1. Develop the complete Section 5.3 with specific fixes for each error type?
2. Add SQL scripts for common fixes?
3. Add examples of using the Developer Tools repair features?
4. Create a troubleshooting decision tree diagram?

Let me know what you'd like me to expand next!
