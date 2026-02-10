# Part 5: Find & Fix Statistics Errors

Over time, errors may appear in the statistical database for various reasons. This part describes the different types of errors, how to identify them, and methods to correct them. Understanding the error type is the first step toward fixing it.

---

**Quick jump table**

| Error Type | Detection | Fix | Auto Fix |
| --- | --- | --- | --- |
| [Missing Statistics (Data Gaps)](#51-missing-statistics) | [gap_detect](#gap_detect) | [gap_fix](#gap_fix) | ❌ |
| [Invalid Data / Spikes](#52-invalid-data--spikes) | [spike_detect](#spike_detect) | [spike_fix](#spike_fix) | ✅ manual |
| [Statistics on Deleted Entities](#53-statistics-on-deleted-entities) | [deleted_detect](#deleted_detect) | [deleted_fix](#deleted_fix) | ❌ |
| [Statistics on Orphaned Entities](#54-statistics-on-orphaned-entities) | [orphan_detect](#orphan_detect) | [orphan_fix](#orphan_fix) | ❌ |
| [Renamed Entities](#55-renamed-entities) | [renamed_detect](#renamed_detect) | [renamed_fix](#renamed_fix) | ✅ manual |
| [Counter Reset Not Detected](#56-counter-reset-not-detected) | [reset_detect](#reset_detect) | [reset_fix](#reset_fix) | ❌ |
| [Wrong Mean Type](#57-wrong-mean-type-circular-vs-arithmetic) | [meantype_detect](#meantype_detect) | [meantype_fix](#meantype_fix) | ❌ |
| [Negative Values in Total_Increasing](#58-negative-values-in-total_increasing) | [neg_detect](#neg_detect) | [neg_fix](#neg_fix) | ❌ |
| [Orphaned Statistics Metadata](#59-orphaned-statistics-metadata) | [orphmeta_detect](#orphmeta_detect) | [orphmeta_fix](#orphmeta_fix) | ❌ |

Errors can be detected by using Developer Tools, SQL queries, or monitoring logs... Some errors can be fixed automatically, others require manual intervention. But the **best practice** is to prevent errors in the first place.

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

Each error manifests differently in the UI and database.
We are going to cover the most common errors in this document and provide information on how to fix them.

>**Note about Unit of Measurement**
    Unit of Measurement selection and modification is a complex process that deserves its own treatment. It is covered separately in the appendices:
    [Appendix 1: How HA Selects and Displays Units](apdx_1_set_units.md) and
    [Appendix 2: Changing Units of Measurement](apdx_2_change_units.md).

---

## **5.1 Missing Statistics**

[Description](#gap_description) | [Causes](#gap_causes) | [Manifestation](#gap_manifestation) | [Detection](#gap_detect) | [Fix](#gap_fix)

<a id="gap_description"></a><span style="font-size: 1.2em; font-weight: bold;">Description</span>  
Periods where no statistics were recorded despite the entity existing and presumably having data. This is a common issue when the integration was not running or home assistant was shutdown.

<a id="gap_causes"></a><span style="font-size: 1.2em; font-weight: bold;">Causes</span>

- Sensor/integration temporarily not delivering data (device offline, network issue)
- Home Assistant was not running
- Entity was excluded from recorder during that period
- Statistics generation was disabled (`state_class` was temporarily removed)
- Database write errors

<a id="gap_manifestation"></a><span style="font-size: 1.2em; font-weight: bold;">Manifestation</span>

**Measurement entities:**

- Visible gaps/holes in history graphs
- Flat lines where interpolation fails
- Missing data points in min/max/mean charts

![Missing Temp](../assets/missing_temp.png)

**Counter entities:**

- Missing bars in bar chart (energy dashboard)
- Discontinuity in cumulative sum (A large variation crushes the values around it.)
- Appears as zero consumption for that period

![Missing states](../assets/missing_states.png)

<a id="gap_detect"></a><span style="font-size: 1.2em; font-weight: bold;">Detection</span>

The SQL queries differs for [measurement](#gap_detect_measurement) and [counter](#gap_detect_counter) entities.

<a id="gap_detect_measurement"></a>**Query for Measurement**

```sql
-- Check for gaps in statistics - SQLite version
-- Only shows rows with gaps (WHERE gap_seconds > 3600)
-- Shows gap size in hours for easier reading
-- Distinguishes between regular gaps (>1h) and large gaps (>2h)
-- Sorts by largest gaps first (most problematic)
WITH gap_analysis AS (
  SELECT 
    datetime(start_ts, 'unixepoch') as period,
    mean,
    start_ts,
    LAG(start_ts) OVER (ORDER BY start_ts) as previous_ts,
    start_ts - LAG(start_ts) OVER (ORDER BY start_ts) as gap_seconds
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.temperature_entree')
)
SELECT 
  period,
  mean,
  gap_seconds / 3600.0 as gap_hours,
  CASE 
    WHEN gap_seconds > 7200 THEN '⚠️ LARGE GAP (>2 hours)'
    WHEN gap_seconds > 3600 THEN '⚠️ GAP DETECTED'
  END as gap_severity
FROM gap_analysis
WHERE gap_seconds > 3600  -- Only show gaps > 1 hour
ORDER BY gap_seconds DESC  -- Show largest gaps first
LIMIT 50;
```

| period | mean | gap_hours | gap_severity |
|---|---|---|---|
|2025-01-22 19:00:00.000000 | 17.69790881333039 | 7 | ⚠️ LARGE GAP (>2 hours) |
|2023-12-03 17:00:00.000000 | 19.725162957811452 | 3 | ⚠️ LARGE GAP (>2 hours) |
|2023-09-21 16:00:00.000000 | 22.09918343405555 | 2 | ⚠️ GAP DETECTED |
|2023-02-05 10:00:00.000000 | 18.800000000000004 | 2 | ⚠️ GAP DETECTED |

<a id="gap_detect_counter"></a>**Query for Counter**

```sql
-- Check gap in counter statistics
-- This version shows the records before and after each gap for better context:
SELECT 
  datetime(s1.start_ts, 'unixepoch', 'localtime') as last_record_before_gap,
  s1.state as state_before,
  s1.sum as sum_before,
  '⚠️ --- GAP ---' as gap_indicator,
  ROUND((s2.start_ts - s1.start_ts) / 3600.0, 1) as gap_hours,
  datetime(s2.start_ts, 'unixepoch', 'localtime') as first_record_after_gap,
  s2.state as state_after,
  s2.sum as sum_after,
  s2.sum - s1.sum as sum_change_across_gap,
  CASE 
    WHEN s2.sum = s1.sum THEN '❌ No consumption recorded (sum unchanged)'
    WHEN s2.state < s1.state THEN '⚠️ Counter may have reset during gap'
    ELSE '⚠️ Consumption during gap unknown'
  END as gap_impact
FROM statistics s1
JOIN statistics s2 ON s2.metadata_id = s1.metadata_id 
  AND s2.start_ts = (
    SELECT MIN(start_ts) 
    FROM statistics 
    WHERE metadata_id = s1.metadata_id 
    AND start_ts > s1.start_ts
  )
WHERE s1.metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.east')
  AND (s2.start_ts - s1.start_ts) > 3600
ORDER BY gap_hours DESC
LIMIT 50;
```

| last before gap | state before | sum before | gap indicator | gap hours | first after gap | state after | sum after | sum change across gap | gap impact |
|---|---|---|---|---|---|---|---|--- | --- |
| 2026-01-15 08:00:00 | 1220.5 | 1220.5 | ⚠️ GAP  | 6.0 | 2026-01-15 14:00:00 | 1250.5 | 1250.5 | 30.0 | ⚠️ Consumption during gap |
| 2026-01-20 03:00:00    | 1305.2       | 1305.2    | ⚠️ GAP | 3.0       | 2026-01-20 06:00:00    | 1305.2      | 1305.2    | 0.0        | ❌ No consumption recorded |

<a id="gap_fix"></a><span style="font-size: 1.2em; font-weight: bold;">Missing Statistics Fix</span>

**For measurement entities** (e.g., temperature, humidity): there is not much that can be done. We cannot guess what the values would have been during the gap. The graph will simply show a blank area for the missing period. This is generally acceptable — it honestly reflects that no data was collected.

**For counter entities** (e.g., energy, water, gas): while we also cannot guess the actual consumption pattern during the gap, the real problem is what happens **after** the gap. The first record after the gap contains the entire accumulated consumption for the missing period in a single hourly entry. This creates an ugly spike on bar graphs (e.g., the energy dashboard showing 30 kWh in one hour instead of ~6 kWh/h spread over 5 hours).

The fix is to **insert interpolated rows** that distribute the consumption evenly across the gap.

**Example** (from the detection query above):

- Gap: 2026-01-15 **08:00** → **14:00** (6 hours gap = 5 missing entries at 09, 10, 11, 12, 13)
- `sum` before gap: 1220.5, after gap: 1250.5 → delta = 30.0
- `state` before gap: 1220.5, after gap: 1250.5 → delta = 30.0
- Interpolation: each missing row gets a consumption increment of 30.0 / 5 = **6.0**

The interpolated rows to insert would be:

| start_ts (as datetime) | state | sum | mean | min | max |
|---|---|---|---|---|---|
| 2026-01-15 09:00:00 | 1226.5 | 1226.5 | NULL | NULL | NULL |
| 2026-01-15 10:00:00 | 1232.5 | 1232.5 | NULL | NULL | NULL |
| 2026-01-15 11:00:00 | 1238.5 | 1238.5 | NULL | NULL | NULL |
| 2026-01-15 12:00:00 | 1244.5 | 1244.5 | NULL | NULL | NULL |
| 2026-01-15 13:00:00 | 1250.5 | 1250.5 | NULL | NULL | NULL |

After inserting these rows, the first record after the gap (14:00) no longer shows a 30 kWh spike — the consumption is spread evenly across the missing hours.

!!! warning "Important"
    - `mean`, `min`, `max` are set to NULL since we don't know the actual values during the gap.
    - The `metadata_id` must match the entity's id in `statistics_meta`.
    - The `start_ts` values must be Unix timestamps (use `strftime('%s', '2026-01-15 09:00:00')` in SQLite).
    - Always work on a **backup copy** of the database first.
    - If `sum` did not change across the gap (delta = 0), there is no consumption to distribute — no fix is needed.

```sql
-- Example: Insert interpolated rows for a counter gap
-- Adjust metadata_id, timestamps, and values to match your specific gap
INSERT INTO statistics (metadata_id, start_ts, created_ts, state, sum, mean, min, max)
VALUES
  (42, strftime('%s', '2026-01-15 09:00:00'), strftime('%s', 'now'), 1226.5, 1226.5, NULL, NULL, NULL),
  (42, strftime('%s', '2026-01-15 10:00:00'), strftime('%s', 'now'), 1232.5, 1232.5, NULL, NULL, NULL),
  (42, strftime('%s', '2026-01-15 11:00:00'), strftime('%s', 'now'), 1238.5, 1238.5, NULL, NULL, NULL),
  (42, strftime('%s', '2026-01-15 12:00:00'), strftime('%s', 'now'), 1244.5, 1244.5, NULL, NULL, NULL),
  (42, strftime('%s', '2026-01-15 13:00:00'), strftime('%s', 'now'), 1250.5, 1250.5, NULL, NULL, NULL);
```

---

<a id="52-invalid-data--spikes"></a>## **5.2 Invalid Data / Spikes**

[Description](#spike_description) | [Causes](#spike_causes) | [Manifestation](#spike_manifestation) | [Detection](#spike_detect) | [Fix](#spike_fix)

<a id="spike_description"></a><span style="font-size: 1.2em; font-weight: bold;">Description</span>  
Statistics contain obviously wrong values due to sensor glitches, measurement errors, or data corruption.

<a id="spike_causes"></a><span style="font-size: 1.2em; font-weight: bold;">Causes</span>

- Sensor hardware malfunction (reading errors)
- Communication interference (corrupt packets)
- Integration bugs (incorrect parsing)
- Sensor calibration issues
- Power fluctuations affecting readings
- No validation in template sensors

<a id="spike_manifestation"></a><span style="font-size: 1.2em; font-weight: bold;">Spike Manifestation</span>

**Measurement entities:**

- Extreme outliers in min/max values
- Impossible values (e.g., -273.15°C temperature, 150% humidity)
- Single extreme spikes followed by return to normal
- Affects mean calculation for that period

```text
Temperature readings:
12:00 → mean: 21.5°C, min: 21.2°C, max: 21.8°C  [NORMAL]
13:00 → mean: 45.2°C, min: 21.5°C, max: 89.7°C  [SPIKE ERROR]
14:00 → mean: 21.8°C, min: 21.6°C, max: 22.0°C  [BACK TO NORMAL]
```

**Counter entities:**

- Massive positive spike followed by negative spike (or vice versa)
- Sum jumps unrealistically high then drops back
- Can trigger false counter reset detection
- Creates artificial consumption peaks in energy dashboard

![counter spike](../assets/counter_spike.png)

<a id="spike_detect"></a><span style="font-size: 1.2em; font-weight: bold;">Spike Detection</span>

The SQL queries differs for [measurement](#spike_detect_measurement) and [counter](#spike_detect_counter) entities.

<a id="spike_detect_measurement"></a><span style="font-size: 1.2em; font-weight: bold;">Spike Detection for Measurement</span>

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

<a id="spike_detect_counter"></a><span style="font-size: 1.2em; font-weight: bold;">Spike Detection for Counter</span>

```sql
-- Find invalid spikes in counter statistics - SQLite
WITH counter_analysis AS (
  SELECT 
    datetime(start_ts, 'unixepoch', 'localtime') as period,
    state,
    sum,
    LAG(state) OVER (ORDER BY start_ts) as previous_state,
    LAG(sum) OVER (ORDER BY start_ts) as previous_sum,
    state - LAG(state) OVER (ORDER BY start_ts) as state_change,
    sum - LAG(sum) OVER (ORDER BY start_ts) as consumption,
    -- Calculate average consumption over last 24 periods
    AVG(sum - LAG(sum) OVER (ORDER BY start_ts)) OVER (
      ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING
    ) as avg_24h_consumption,
    -- Calculate standard deviation
    (sum - LAG(sum) OVER (ORDER BY start_ts)) as hourly_consumption
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
)
SELECT 
  period,
  state as counter_value,
  sum as cumulative_sum,
  consumption as hourly_consumption,
  ROUND(avg_24h_consumption, 2) as avg_24h,
  ROUND(consumption / NULLIF(avg_24h_consumption, 0), 1) as spike_multiplier,
  CASE 
    WHEN consumption IS NULL THEN 'First record'
    WHEN avg_24h_consumption = 0 THEN '⚠️ No baseline yet'
    WHEN consumption < 0 THEN '❌ NEGATIVE consumption (impossible!)'
    WHEN consumption > avg_24h_consumption * 10 THEN '❌ EXTREME SPIKE (>10x normal)'
    WHEN consumption > avg_24h_consumption * 5 THEN '⚠️ LARGE SPIKE (>5x normal)'
    WHEN consumption > avg_24h_consumption * 3 THEN '⚠️ SPIKE DETECTED (>3x normal)'
    WHEN ABS(state_change) < 0.001 AND consumption > 0 THEN '⚠️ Sum increased but state unchanged'
    ELSE 'OK'
  END as spike_status,
  CASE 
    WHEN consumption < 0 THEN 'Counter decreased (hardware error or missed reset)'
    WHEN consumption > avg_24h_consumption * 10 THEN 'Unrealistic consumption spike'
    WHEN ABS(state_change) < 0.001 AND consumption > 0 THEN 'Sum/state mismatch'
    ELSE ''
  END as issue_description
FROM counter_analysis
WHERE consumption IS NOT NULL
  AND avg_24h_consumption > 0
  AND (
    consumption < 0 
    OR consumption > avg_24h_consumption * 3
    OR (ABS(state_change) < 0.001 AND consumption > 0)
  )
ORDER BY ABS(consumption / NULLIF(avg_24h_consumption, 1)) DESC
LIMIT 50;
```

| period              | counter_value | cumulative_sum | hourly_consumption | avg_24h | spike_multiplier | spike_status              | issue_description |
|---------------------|---------------|----------------|-------------------|---------|------------------|---------------------------|-------------------|
| 2026-01-15 13:00:00 | 1255.2        | 1255.2         | 2500.0            | 2.5     | 1000.0           | ❌ EXTREME SPIKE (>10x)  | Unrealistic consumption spike  |
| 2026-01-20 08:00:00 | 1305.8        | 1305.8         | -45.2             | 2.3     | -19.7            | ❌ NEGATIVE consumption  | Counter decreased |
| 2026-02-01 14:00:00 | 1450.0        | 1450.0         | 18.5              | 2.4     | 7.7              | ⚠️ LARGE SPIKE (>5x)    | |

<a id="spike_fix"></a><span style="font-size: 1.2em; font-weight: bold;">Spike Fix</span>

**For measurement entities** (e.g., temperature, humidity): the simplest fix is to **delete the spike record**. Since measurement statistics are independent of each other (no cumulative values), removing one row just creates a small gap in the graph — which is preferable to a misleading spike.

```sql
-- Delete a specific spike record for a measurement entity
-- First identify the spike using the detection query, then delete by start_ts
DELETE FROM statistics
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.temperature')
  AND start_ts = strftime('%s', '2026-01-15 13:00:00');
```

**For counter entities** (e.g., energy, water, gas): spikes in counters typically appear as a glitch pair — a spike record with abnormally high consumption followed by a compensating record with negative or near-zero consumption. Simply deleting these records would break the cumulative `sum` chain. Instead, **replace both records with linearly interpolated values**.

**Example:**

Suppose the detection query found a spike at 13:00 with consumption of 2500 kWh (normal baseline ~2.5 kWh/h), followed by a compensating drop at 14:00:

| period | sum | consumption | status |
|---|---|---|---|
| 12:00 | 1250.0 | 2.5 | OK (before spike) |
| 13:00 | 3750.0 | 2500.0 | ❌ SPIKE |
| 14:00 | 1255.0 | -2495.0 | ❌ COMPENSATION |
| 15:00 | 1257.5 | 2.5 | OK (after glitch) |

The fix: replace the two glitch records (13:00 and 14:00) with interpolated values based on the records before (12:00) and after (15:00):

- Total real consumption over 3 hours (12:00→15:00): 1257.5 - 1250.0 = **7.5**
- Per hour: 7.5 / 3 = **2.5**
- Interpolated 13:00: sum = 1250.0 + 2.5 = **1252.5**
- Interpolated 14:00: sum = 1250.0 + 5.0 = **1255.0**

```sql
-- Fix counter spike: update the two glitch records with interpolated values
-- Step 1: Update the spike record
UPDATE statistics
SET state = 1252.5, sum = 1252.5, mean = NULL, min = NULL, max = NULL
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
  AND start_ts = strftime('%s', '2026-01-15 13:00:00');

-- Step 2: Update the compensation record
UPDATE statistics
SET state = 1255.0, sum = 1255.0, mean = NULL, min = NULL, max = NULL
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
  AND start_ts = strftime('%s', '2026-01-15 14:00:00');
```

!!! warning "Important"
    - Always work on a **backup copy** of the database first.
    - Verify the records before and after the glitch are valid before interpolating.
    - If the spike is a single record (no compensation drop), you can simply UPDATE it with an interpolated value based on the surrounding records.
    - After fixing, re-run the detection query to confirm the spike is gone.

---

## **5.3 Statistics on Deleted Entities**

[Description](#deleted_description) | [Causes](#deleted_causes) | [Manifestation](#deleted_manifestation) | [Detection](#deleted_detect) | [Fix](#deleted_fix)

<a id="deleted_description"></a><span style="font-size: 1.2em; font-weight: bold;">Description</span>  
Statistics remain in the database for entities that no longer exist in Home Assistant.

<a id="deleted_causes"></a><span style="font-size: 1.2em; font-weight: bold;">Causes</span>

- Entity was deleted or removed from configuration
- Integration was uninstalled
- Device was removed
- Entity ID was changed without migration
- Statistics were not purged when entity was deleted

<a id="deleted_manifestation"></a><span style="font-size: 1.2em; font-weight: bold;">Deleted Entities Manifestation</span>

- Statistics shown in Developer Tools → Statistics for non-existent entities
- Orphaned `statistic_id` entries in `statistics_meta`
- Wasted database space
- Confusing in energy dashboard or history graphs
- Entity appears in statistics but not in entity list

**Example:**

statistics_meta table:

| statistic_id                  | source   | unit | has_sum | |
|-------------------------------|----------|------|---------| |
| sensor.old_temperature        | recorder | °C   | 0       | ← Entity deleted |
| sensor.removed_power_meter    | recorder | W    | 0       | ← Integration removed |
| sensor.current_temperature    | recorder | °C   | 0       | ← Still exists |

<a id="deleted_detect"></a><span style="font-size: 1.2em; font-weight: bold;">Detection</span>

```sql
-- Find statistics for entities that no longer exist in Home Assistant
-- indicates number of records attached to the deleted entity
SELECT sm.id as stats_meta_id, 
       sm.statistic_id, 
       sm.source, 
       sm.unit_of_measurement,
       COUNT(s.id) as record_count,
       MIN(datetime(s.start_ts, 'unixepoch')) as first_record,
       MAX(datetime(s.start_ts, 'unixepoch')) as last_record
FROM statistics_meta sm
LEFT JOIN states_meta stm ON sm.statistic_id = stm.entity_id
LEFT JOIN statistics s ON sm.id = s.metadata_id
WHERE stm.entity_id IS NULL
GROUP BY sm.id, sm.statistic_id, sm.source, sm.unit_of_measurement
ORDER BY sm.statistic_id;
```

| statistic_id           | record_count | Issue |
|------------------------|--------------|-------|
| sensor.old_temperature | 8760         | ← Has lots of data |
| sensor.failed_sensor   | 0            | ← Never generated data |

<a id="deleted_fix"></a><span style="font-size: 1.2em; font-weight: bold;">Deleted Entities Fix</span>

Since the entity no longer exists, the statistics data is no longer useful. The fix is to **delete all associated records** from the three statistics tables: `statistics`, `statistics_short_term`, and `statistics_meta`.

The deletion must be done in the correct order — data tables first, then metadata — because `statistics` and `statistics_short_term` reference `statistics_meta` via `metadata_id`.

```sql
-- Step 1: Delete long-term statistics
DELETE FROM statistics
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.old_temperature');

-- Step 2: Delete short-term statistics
DELETE FROM statistics_short_term
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.old_temperature');

-- Step 3: Delete the metadata entry
DELETE FROM statistics_meta
WHERE statistic_id = 'sensor.old_temperature';
```

!!! warning "Important"
    - Always work on a **backup copy** of the database first.
    - Use the detection query to identify the exact `statistic_id` before deleting.
    - Delete data tables (`statistics`, `statistics_short_term`) **before** `statistics_meta` to avoid foreign key issues.
    - After deleting, restart Home Assistant for changes to take effect.

---

## **5.4 Statistics on Orphaned Entities**

[Description](#orphan_description) | [Causes](#orphan_causes) | [Manifestation](#orphan_manifestation) | [Detection](#orphan_detect) | [Fix](#orphan_fix)

<a id="orphan_description"></a><span style="font-size: 1.2em; font-weight: bold;">Description</span>  
Orphaned entities are entities that exist in the database but are no longer claimed by any active integration. Unlike deleted entities (section 5.3) where the entity record is completely removed, orphaned entities remain in the `states_meta` table in a "zombie" state — still present but disconnected from any working integration.

Home Assistant considers an entity orphaned only after it has been unclaimed since the last restart. At restart, HA checks whether each entity is still claimed by an integration. If not, it writes a final state record with `state = NULL` to the `states` table, effectively marking the entity as orphaned.

Orphan statistics are the statistics records associated with these orphaned entities. They are typically not useful to retain because the source integration is no longer providing data and the entity will never receive new state updates.

<a id="orphan_causes"></a><span style="font-size: 1.2em; font-weight: bold;">Causes</span>

- Integration was removed or uninstalled
- Integration is broken or no longer loading
- Device was physically disconnected and removed from the integration
- Integration was disabled in Settings → Devices & Services
- HACS custom integration was uninstalled
- Entity was created by an automation/script that no longer exists
- Hardware failure on a device (e.g., Zigbee device died) and device was removed

<a id="orphan_manifestation"></a><span style="font-size: 1.2em; font-weight: bold;">Manifestation</span>

- Entity appears in Settings → Entities with state "unavailable" or "unknown" persistently
- After a restart, entity state becomes `NULL` in the database
- Statistics continue to exist in `statistics_meta` and `statistics` tables but no new data is generated
- Entity may still appear in energy dashboard or history graphs with stale data
- Developer Tools → Statistics shows the entity but with no recent records
- Wasted database space from historical statistics that cannot be correlated with current system state
- Confusing entries when querying statistics or browsing entity lists

**Example:**

After removing a Zigbee power meter integration and restarting HA:

| Table | Entry | State |
|-------|-------|-------|
| `states_meta` | `sensor.zigbee_power` | exists |
| `states` (latest) | `sensor.zigbee_power` | `NULL` ← marked orphaned at restart |
| `statistics_meta` | `sensor.zigbee_power` | exists (has_sum=1) |
| `statistics` | `sensor.zigbee_power` | 8760 records ← historical data, no new data coming |

<a id="orphan_detect"></a><span style="font-size: 1.2em; font-weight: bold;">Detection</span>

Since HA marks orphaned entities with `state = NULL` at restart (see Description above), the detection method is: **find entities whose most recent state is NULL**, then check if they have associated statistics records.

The query below uses a subquery to find the latest `state_id` for each entity, ensuring we only check the most recent state. It then joins with `statistics_meta` and `statistics` to show how many statistics records are associated with each orphaned entity.

```sql
-- Find orphaned entities that have associated statistics
-- An orphaned entity has NULL as its most recent state (set by HA at restart)
SELECT stm.entity_id,
       st.state,
       datetime(st.last_updated_ts, 'unixepoch') as last_updated,
       sm.statistic_id,
       COUNT(s.id) as statistics_count
FROM states_meta stm
JOIN states st ON stm.metadata_id = st.metadata_id
LEFT JOIN statistics_meta sm ON stm.entity_id = sm.statistic_id
LEFT JOIN statistics s ON sm.id = s.metadata_id
WHERE st.state IS NULL
  AND st.state_id = (
    SELECT state_id FROM states 
    WHERE metadata_id = stm.metadata_id 
    ORDER BY last_updated_ts DESC LIMIT 1
  )
GROUP BY stm.entity_id, st.state, st.last_updated_ts, sm.statistic_id
ORDER BY st.last_updated_ts DESC;
```

The `statistics_count` column shows how many long-term statistics records exist for each orphaned entity. Entities with `statistic_id = NULL` and `statistics_count = 0` are orphaned but have no statistics — they can be safely ignored in this context.

<a id="orphan_fix"></a><span style="font-size: 1.2em; font-weight: bold;">Orphaned Entities Fix</span>

The fix is the same as for deleted entities (section 5.3): **delete all associated records** from the three statistics tables in the correct order.

```sql
-- Step 1: Delete long-term statistics
DELETE FROM statistics
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.zigbee_power');

-- Step 2: Delete short-term statistics
DELETE FROM statistics_short_term
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.zigbee_power');

-- Step 3: Delete the metadata entry
DELETE FROM statistics_meta
WHERE statistic_id = 'sensor.zigbee_power';
```

!!! warning "Important"
    - Always work on a **backup copy** of the database first.
    - Use the detection query to identify the exact `statistic_id` before deleting.
    - Delete data tables (`statistics`, `statistics_short_term`) **before** `statistics_meta`.
    - After deleting, restart Home Assistant for changes to take effect.
    - You may also want to remove the orphaned entity itself via Settings → Entities → select entity → Delete.

---

## **5.5 Renamed Entities**

[Description](#renamed_description) | [Causes](#renamed_causes) | [Manifestation](#renamed_manifestation) | [Detection](#renamed_detect) | [Fix](#renamed_fix)

<a id="renamed_description"></a><span style="font-size: 1.2em; font-weight: bold;">Description</span>  
Entity was renamed, but statistics remain under the old `entity_id`, causing apparent data loss.

<a id="renamed_causes"></a><span style="font-size: 1.2em; font-weight: bold;">Causes</span>

- Entity renamed via UI (Settings → Entities)
- Entity ID changed in configuration.yaml
- Integration reorganized entity IDs
- Device renamed causing entity_id change

<a id="renamed_manifestation"></a><span style="font-size: 1.2em; font-weight: bold;">Renamed Entities Manifestation</span>

- Statistics exist for old entity_id but not new one
- Historical data appears "missing" for renamed entity
- Two entries appear: one with history (old name), one without (new name)
- Energy dashboard loses tracking continuity
- Automations referencing old statistics fail

**Example:**

Old: sensor.living_room_temperature
New: sensor.lounge_temperature

statistics_meta shows:

| statistic_id                     | Last record       | |
|----------------------------------|-------------------|---|
| sensor.living_room_temperature   | 2025-12-15        | ← All history here |
| sensor.lounge_temperature        | 2025-12-16 →      | ← New data here |

<a id="renamed_detect"></a><span style="font-size: 1.2em; font-weight: bold;">Renamed Entities Detection</span>

```sql
-- Find statistics pairs that might be a renamed entity
-- Looks for: same unit/has_sum, one stopped recording, the other started around the same time
WITH entity_ranges AS (
  SELECT 
    sm.id as meta_id,
    sm.statistic_id,
    sm.unit_of_measurement,
    sm.has_sum,
    MIN(s.start_ts) as first_record,
    MAX(s.start_ts) as last_record
  FROM statistics_meta sm
  JOIN statistics s ON sm.id = s.metadata_id
  GROUP BY sm.id
)
SELECT 
  old.statistic_id as old_name,
  datetime(old.last_record, 'unixepoch', 'localtime') as old_last_record,
  new.statistic_id as new_name,
  datetime(new.first_record, 'unixepoch', 'localtime') as new_first_record,
  ROUND((new.first_record - old.last_record) / 3600.0, 1) as gap_hours
FROM entity_ranges old
JOIN entity_ranges new 
  ON old.unit_of_measurement = new.unit_of_measurement
  AND old.has_sum = new.has_sum
  AND old.statistic_id != new.statistic_id
  AND old.last_record < new.first_record          -- old stopped before new started
  AND (new.first_record - old.last_record) < 86400 -- within 24 hours
ORDER BY gap_hours;
```

<a id="renamed_fix"></a><span style="font-size: 1.2em; font-weight: bold;">Renamed Entities Fix</span>

The fix is to **update the `statistic_id`** in `statistics_meta` from the old name to the new name. This consolidates all historical data under the new entity name.

Before merging, verify that the new entity already has a `statistics_meta` entry. If it does, you need to **move the statistics records** from the old metadata_id to the new one, then delete the old metadata entry. If it doesn't, a simple rename suffices.

**Case 1: New entity has no existing statistics** (simple rename)

```sql
-- Simply rename the statistic_id in metadata
UPDATE statistics_meta
SET statistic_id = 'sensor.lounge_temperature'
WHERE statistic_id = 'sensor.living_room_temperature';
```

**Case 2: New entity already has statistics** (merge)

```sql
-- Step 1: Move old statistics to the new metadata_id
UPDATE statistics
SET metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.lounge_temperature')
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.living_room_temperature');

-- Step 2: Move old short-term statistics
UPDATE statistics_short_term
SET metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.lounge_temperature')
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.living_room_temperature');

-- Step 3: Delete the old metadata entry
DELETE FROM statistics_meta
WHERE statistic_id = 'sensor.living_room_temperature';
```

!!! warning "Important"
    - Always work on a **backup copy** of the database first.
    - Verify both entities have the same `unit_of_measurement` and `has_sum` before merging.
    - Check for overlapping timestamps — if both old and new have records for the same period, you'll need to delete the duplicates before merging.
    - After merging, restart Home Assistant for changes to take effect.

---

## **5.6 Counter Reset Not Detected**

[Description](#reset_description) | [Causes](#reset_causes) | [Manifestation](#reset_manifestation) | [Detection](#reset_detect) | [Fix](#reset_fix)

<a id="reset_description"></a><span style="font-size: 1.2em; font-weight: bold;">Description</span>  
A `total_increasing` counter reset to zero, but the statistics system didn't detect it, resulting in negative or missing consumption data.

<a id="reset_causes"></a><span style="font-size: 1.2em; font-weight: bold;">Causes</span>

- Reset was too small (< 10% threshold)
- Counter decremented instead of resetting (hardware issue)
- Statistics compiler wasn't running during reset
- Database wasn't updated with `last_reset` timestamp
- Sensor temporarily reported unavailable during reset

<a id="reset_manifestation"></a><span style="font-size: 1.2em; font-weight: bold;">Counter Reset Manifestation</span>

- Negative hourly consumption values in energy dashboard
- Sum stops increasing or shows incorrect totals
- Bar chart shows no consumption when there should be
- State value is lower than previous, but sum didn't adjust

**Example:**

```text
Counter readings:
10:00 → state: 1250 kWh, sum: 1250 kWh
11:00 → state: 1255 kWh, sum: 1255 kWh (+5 kWh consumption) ✓
12:00 → state: 5 kWh,    sum: 1255 kWh (reset not detected!)
13:00 → state: 8 kWh,    sum: 1258 kWh (+3 kWh consumption) ✓

Expected at 12:00: sum should handle reset gracefully
Actual: sum froze, hourly consumption = 0
```

<a id="reset_detect"></a><span style="font-size: 1.2em; font-weight: bold;">Counter Reset Detection</span>

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

<a id="reset_fix"></a><span style="font-size: 1.2em; font-weight: bold;">Counter Reset Fix</span>

When a counter reset is missed, the `sum` freezes at its pre-reset value and subsequent consumption is lost. The fix is to **recalculate `sum` from the reset point onward**, adding the post-reset state changes back into the cumulative sum.

Using the example above (reset at 12:00, state dropped from 1255 to 5):

| period | state | sum (broken) | sum (fixed) | explanation |
|---|---|---|---|---|
| 11:00 | 1255 | 1255 | 1255 | OK — last record before reset |
| 12:00 | 5 | 1255 | 1260 | Reset: sum = 1255 + 5 (new state) |
| 13:00 | 8 | 1258 | 1263 | sum = 1260 + (8 - 5) = 1263 |

```sql
-- Fix missed counter reset: recalculate sum from the reset point onward
-- Step 1: Identify the pre-reset sum (last good sum before the reset)
-- In this example: pre_reset_sum = 1255, reset happened at start_ts for 12:00

-- Step 2: Update the reset record
-- New sum = pre_reset_sum + new_state_after_reset
UPDATE statistics
SET sum = 1260.0
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
  AND start_ts = strftime('%s', '2026-01-15 12:00:00');

-- Step 3: Recalculate all subsequent records
-- For each record after the reset, sum = previous_sum + (state - previous_state)
-- This must be done sequentially, record by record, or with a cumulative window:
UPDATE statistics
SET sum = 1260.0 + (state - 5.0)
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
  AND start_ts > strftime('%s', '2026-01-15 12:00:00');
```

!!! note "Simplified example"
    The Step 3 query above works when `state` is a monotonically increasing counter (each record's consumption = `state - state_at_reset`). For counters with multiple resets or complex patterns, you may need to recalculate each record individually using a script or spreadsheet.

!!! warning "Important"
    - Always work on a **backup copy** of the database first.
    - Verify the pre-reset `sum` value is correct before recalculating.
    - After fixing, check the energy dashboard to confirm consumption values look reasonable.
    - If many records need fixing, consider using the HA `developer-tools/statistics` "Adjust sum" feature instead of manual SQL.

---

## **5.7 Wrong Mean Type (Circular vs Arithmetic)**

[Description](#meantype_description) | [Causes](#meantype_causes) | [Manifestation](#meantype_manifestation) | [Detection](#meantype_detect) | [Fix](#meantype_fix)

<a id="meantype_description"></a><span style="font-size: 1.2em; font-weight: bold;">Description</span>  
Non-angular data is being processed with circular mean, or angular data with arithmetic mean.

<a id="meantype_causes"></a><span style="font-size: 1.2em; font-weight: bold;">Causes</span>

- Incorrect `device_class` configuration
- Template sensor without proper device_class
- Integration bug assigning wrong device_class
- Manual database modification error

<a id="meantype_manifestation"></a><span style="font-size: 1.2em; font-weight: bold;">Wrong Mean Type Manifestation</span>

- Angular sensors show impossible mean values
  - Wind direction mean of 520° (should be 0-360°)
  - Compass heading with negative values
- Non-angular sensors averaged incorrectly
  - Temperature treated as circular (rare but possible configuration error)

**Example:**

```text
Wind Direction Sensor with mean_type=1 (arithmetic) - WRONG:
0° + 350° + 340° = 690° / 3 = 230°  ← WRONG! (should be ~350°)

Wind Direction Sensor with mean_type=2 (circular) - CORRECT:
0° + 350° + 340° → vectors → 350°  ← CORRECT!
```

<a id="meantype_detect"></a><span style="font-size: 1.2em; font-weight: bold;">Wrong Mean Type Detection</span>

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

<a id="meantype_fix"></a><span style="font-size: 1.2em; font-weight: bold;">Wrong Mean Type Fix</span>

The fix has two parts: correct the `mean_type` in metadata, and deal with the incorrectly computed historical statistics.

**Step 1: Fix the mean_type in metadata**

```sql
-- Change mean_type to circular (2) for a wind direction sensor
UPDATE statistics_meta
SET mean_type = 2
WHERE statistic_id = 'sensor.wind_direction';
```

**Step 2: Delete incorrect historical statistics**

The existing `mean`, `min`, and `max` values were computed with the wrong averaging method and cannot be corrected with a simple SQL update (circular mean requires trigonometric functions not available in SQLite). The safest approach is to **delete the incorrect records** and let HA rebuild them going forward.

```sql
-- Delete statistics computed with wrong mean type
DELETE FROM statistics
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.wind_direction');

DELETE FROM statistics_short_term
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.wind_direction');
```

!!! note
    Historical data will be lost. If the sensor has only been running for a short time, this is acceptable. If you need to preserve history, the only option is to recalculate the circular means externally (e.g., with Python) and update each record individually.

!!! warning "Important"
    - Always work on a **backup copy** of the database first.
    - Fix the `device_class` in your HA configuration **before** correcting the database, otherwise HA will recreate the wrong mean_type.
    - After fixing, restart Home Assistant for changes to take effect.

---

## **5.8 Negative Values in Total_Increasing**

[Description](#neg_description) | [Causes](#neg_causes) | [Manifestation](#neg_manifestation) | [Detection](#neg_detect) | [Fix](#neg_fix)

<a id="neg_description"></a><span style="font-size: 1.2em; font-weight: bold;">Description</span>  
A `total_increasing` counter shows negative state or sum values, which violates the monotonic increase constraint.

<a id="neg_causes"></a><span style="font-size: 1.2em; font-weight: bold;">Causes</span>

- Sensor returned negative value due to hardware error
- Template calculation error (e.g., subtraction instead of addition)
- Database corruption
- Manual statistics injection error
- Counter rollover with incorrect handling

<a id="neg_manifestation"></a><span style="font-size: 1.2em; font-weight: bold;">Negative Values Manifestation</span>

- Validation errors in Developer Tools → Statistics
- Energy dashboard shows negative consumption
- Bar charts with negative bars
- Warning messages in Home Assistant logs
- Impossible physical values (negative total energy consumed)

**Example:**

statistics table:

| start_ts   | state  | sum    | Issue                    |
|------------|--------|--------|--------------------------|
| 1735574400 | 1250.5 | 1250.5 | OK                       |
| 1735578000 | -5.2   | 1245.3 | ⚠️ Negative state value! |
| 1735581600 | 8.7    | 1254.0 | Recovered                |

<a id="neg_detect"></a><span style="font-size: 1.2em; font-weight: bold;">Negative Values Detection</span>

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

<a id="neg_fix"></a><span style="font-size: 1.2em; font-weight: bold;">Negative Values Fix</span>

Negative values in a `total_increasing` counter are physically impossible (e.g., you can't "un-consume" energy). The fix depends on whether the negative value is a transient glitch or a persistent error.

**Single glitch record** (negative state surrounded by valid records): replace with interpolated values, same approach as the spike fix in section 5.2.

```sql
-- Replace a single negative-state record with interpolated value
-- Use the average of the previous and next sum values
UPDATE statistics
SET state = (
  SELECT (prev.sum + next.sum) / 2.0
  FROM statistics prev, statistics next
  WHERE prev.metadata_id = statistics.metadata_id
    AND next.metadata_id = statistics.metadata_id
    AND prev.start_ts < statistics.start_ts
    AND next.start_ts > statistics.start_ts
  ORDER BY prev.start_ts DESC, next.start_ts ASC
  LIMIT 1
),
sum = (
  SELECT (prev.sum + next.sum) / 2.0
  FROM statistics prev, statistics next
  WHERE prev.metadata_id = statistics.metadata_id
    AND next.metadata_id = statistics.metadata_id
    AND prev.start_ts < statistics.start_ts
    AND next.start_ts > statistics.start_ts
  ORDER BY prev.start_ts DESC, next.start_ts ASC
  LIMIT 1
)
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
  AND start_ts = strftime('%s', '2026-01-15 11:00:00');
```

**Multiple consecutive negative records**: it may be simpler to delete them and accept a gap.

```sql
DELETE FROM statistics
WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
  AND state < 0;
```

!!! warning "Important"
    - Always work on a **backup copy** of the database first.
    - Fix the root cause (sensor config, template error) **before** correcting the database.
    - After fixing, verify the `sum` chain is still monotonically increasing.

---

## **5.9 Orphaned Statistics Metadata**

[Description](#orphmeta_description) | [Causes](#orphmeta_causes) | [Manifestation](#orphmeta_manifestation) | [Detection](#orphmeta_detect) | [Fix](#orphmeta_fix)

<a id="orphmeta_description"></a><span style="font-size: 1.2em; font-weight: bold;">Description</span>  
Entries in `statistics_meta` table have no corresponding records in `statistics` or `statistics_short_term` tables.

<a id="orphmeta_causes"></a><span style="font-size: 1.2em; font-weight: bold;">Causes</span>

- Statistics were manually deleted but metadata wasn't
- Purge operation incomplete or interrupted
- Entity created but never generated statistics
- Database cleanup tools only cleaned data tables
- Statistics generation started but immediately failed

<a id="orphmeta_manifestation"></a><span style="font-size: 1.2em; font-weight: bold;">Manifestation</span>

- Metadata entries with zero statistics records
- Wasted database space (minimal but clutters queries)
- Confusion when querying metadata
- Gaps between expected and actual statistics count

**Example:**

statistics_meta entry exists:

| id | statistic_id              | unit | has_sum |
|----|---------------------------|------|---------|
| 99 | sensor.phantom_sensor     | kWh  | 1       |

But querying statistics:

```sql
SELECT COUNT(*) FROM statistics WHERE metadata_id = 99;
Result: 0  ← No statistics ever recorded!
```

<a id="orphmeta_detect"></a><span style="font-size: 1.2em; font-weight: bold;">Detection</span>

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

<a id="orphmeta_fix"></a><span style="font-size: 1.2em; font-weight: bold;">Fix</span>

Since there are no statistics records associated with these metadata entries, simply **delete the orphaned rows** from `statistics_meta`.

```sql
-- Delete orphaned metadata entries (those with no statistics in either table)
DELETE FROM statistics_meta
WHERE id NOT IN (SELECT DISTINCT metadata_id FROM statistics)
  AND id NOT IN (SELECT DISTINCT metadata_id FROM statistics_short_term);
```

!!! warning "Important"
    - Always work on a **backup copy** of the database first.
    - After deleting, restart Home Assistant for changes to take effect.

---

**Previous** - [Part 4: Best Practices and Troubleshooting](part4_practices_troubleshooting.md)
**Next** - [Appendix 1: Setting Units of Measurement](apdx_1_set_units.md)
