# error

## 1 Gap in statistic

### for measurements

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

```sql
-- Check for gaps in statistics sama as above - MariaDB version
WITH gap_analysis AS (
  SELECT 
    FROM_UNIXTIME(start_ts) as period,
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

### for counter

```sql
-- Check for gaps in counter statistics (only show gaps) - SQLite
WITH gap_analysis AS (
  SELECT 
    datetime(start_ts, 'unixepoch', 'localtime') as period,
    state,
    sum,
    sum - LAG(sum) OVER (ORDER BY start_ts) as consumption,
    start_ts,
    LAG(start_ts) OVER (ORDER BY start_ts) as previous_ts,
    start_ts - LAG(start_ts) OVER (ORDER BY start_ts) as gap_seconds
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.east')
)
SELECT 
  period,
  state as counter_value,
  sum as cumulative_sum,
  consumption as period_consumption,
  gap_seconds / 3600.0 as gap_hours,
  CASE 
    WHEN gap_seconds > 7200 THEN '⚠️ LARGE GAP (>2 hours)'
    WHEN gap_seconds > 3600 THEN '⚠️ GAP DETECTED'
  END as gap_severity,
  '❌ Missing consumption data for this period' as impact
FROM gap_analysis
WHERE gap_seconds > 3600  -- Only show gaps > 1 hour
ORDER BY gap_seconds DESC
LIMIT 50;
```

```sql
-- Check for gaps in counter statistics (only show gaps) - MariaDB
WITH gap_analysis AS (
  SELECT 
    FROM_UNIXTIME(start_ts) as period,
    state,
    sum,
    sum - LAG(sum) OVER (ORDER BY start_ts) as consumption,
    start_ts,
    LAG(start_ts) OVER (ORDER BY start_ts) as previous_ts,
    start_ts - LAG(start_ts) OVER (ORDER BY start_ts) as gap_seconds
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.east')
)
SELECT 
  period,
  state as counter_value,
  sum as cumulative_sum,
  consumption as period_consumption,
  gap_seconds / 3600.0 as gap_hours,
  CASE 
    WHEN gap_seconds > 7200 THEN '⚠️ LARGE GAP (>2 hours)'
    WHEN gap_seconds > 3600 THEN '⚠️ GAP DETECTED'
  END as gap_severity,
  '❌ Missing consumption data for this period' as impact
FROM gap_analysis
WHERE gap_seconds > 3600  -- Only show gaps > 1 hour
ORDER BY gap_seconds DESC
LIMIT 50;
```

```sql
-- Show gaps with before/after context - SQLite
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
WHERE s1.metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.energy_total')
  AND (s2.start_ts - s1.start_ts) > 3600
ORDER BY gap_hours DESC
LIMIT 50;
```

```sql
-- Show gaps with before/after context - MariaDB
SELECT 
  FROM_UNIXTIME(s1.start_ts) as last_record_before_gap,
  s1.state as state_before,
  s1.sum as sum_before,
  '⚠️ --- GAP ---' as gap_indicator,
  ROUND((s2.start_ts - s1.start_ts) / 3600.0, 1) as gap_hours,
  FROM_UNIXTIME(s2.start_ts) as first_record_after_gap,
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

## 2 Invalid Data / Spikes

### for measurement

```sql
-- Find measurement outliers (values > 3 standard deviations from mean)
WITH stats AS (
  SELECT 
    AVG(mean) as avg_mean,
    AVG(mean * mean) - AVG(mean) * AVG(mean) as variance
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.e3_vitocal_boiler_supply_temperature')
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

### for counters

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
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.east')
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

```sql
-- Find invalid spikes in counter statistics - MariaDB (corrected)
WITH consumption_calc AS (
  -- Step 1: Calculate consumption for each period
  SELECT 
    FROM_UNIXTIME(start_ts) as period,
    start_ts,
    state,
    sum,
    LAG(state) OVER (ORDER BY start_ts) as previous_state,
    LAG(sum) OVER (ORDER BY start_ts) as previous_sum,
    state - LAG(state) OVER (ORDER BY start_ts) as state_change,
    sum - LAG(sum) OVER (ORDER BY start_ts) as consumption
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.east')
),
counter_analysis AS (
  -- Step 2: Calculate average consumption over last 24 periods
  SELECT 
    period,
    state,
    sum,
    previous_state,
    previous_sum,
    state_change,
    consumption,
    AVG(consumption) OVER (
      ORDER BY start_ts
      ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING
    ) as avg_24h_consumption
  FROM consumption_calc
)
SELECT 
  period,
  state as counter_value,
  sum as cumulative_sum,
  ROUND(consumption, 2) as hourly_consumption,
  ROUND(avg_24h_consumption, 2) as avg_24h,
  ROUND(consumption / NULLIF(avg_24h_consumption, 0), 1) as spike_multiplier,
  CASE 
    WHEN consumption IS NULL THEN 'First record'
    WHEN avg_24h_consumption = 0 OR avg_24h_consumption IS NULL THEN '⚠️ No baseline yet'
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

```sql
-- Detect spike + recovery pattern (glitch signature) - SQLite (corrected)
WITH consumption_calc AS (
  -- Step 1: Calculate consumption and next consumption
  SELECT 
    datetime(start_ts, 'unixepoch', 'localtime') as period,
    start_ts,
    state,
    sum,
    sum - LAG(sum) OVER (ORDER BY start_ts) as consumption,
    LEAD(sum) OVER (ORDER BY start_ts) - sum as next_consumption
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.east')
),
consumption_with_avg AS (
  -- Step 2: Calculate rolling average
  SELECT 
    period,
    state,
    sum,
    consumption,
    next_consumption,
    AVG(consumption) OVER (
      ORDER BY start_ts
      ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING
    ) as avg_consumption
  FROM consumption_calc
)
SELECT 
  period,
  state,
  sum,
  ROUND(consumption, 2) as this_period_consumption,
  ROUND(next_consumption, 2) as next_period_consumption,
  ROUND(avg_consumption, 2) as baseline_avg,
  CASE 
    WHEN consumption > avg_consumption * 5 
         AND next_consumption < 0 
         AND ABS(next_consumption) > avg_consumption * 3
    THEN '❌ SPIKE + DROP GLITCH DETECTED'
    WHEN consumption > avg_consumption * 5 
         AND next_consumption < avg_consumption * 0.2
    THEN '⚠️ SPIKE followed by very low consumption'
    WHEN consumption < 0 
         AND next_consumption > avg_consumption * 3
    THEN '⚠️ DROP followed by spike (inverse glitch)'
    ELSE 'Potential issue'
  END as glitch_pattern,
  'Data integrity compromised - manual correction may be needed' as recommendation
FROM consumption_with_avg
WHERE avg_consumption > 0
  AND (
    -- Spike followed by negative consumption
    (consumption > avg_consumption * 5 AND next_consumption < 0) OR
    -- Negative consumption followed by spike
    (consumption < 0 AND next_consumption > avg_consumption * 3) OR
    -- Extreme spike followed by near-zero
    (consumption > avg_consumption * 10 AND next_consumption < avg_consumption * 0.2)
  )
ORDER BY period DESC
LIMIT 50;
```

```sql
-- Detect spike + recovery pattern (glitch signature) - MariaDB (corrected)
WITH consumption_calc AS (
  -- Step 1: Calculate consumption and next consumption
  SELECT 
    FROM_UNIXTIME(start_ts) as period,
    start_ts,
    state,
    sum,
    sum - LAG(sum) OVER (ORDER BY start_ts) as consumption,
    LEAD(sum) OVER (ORDER BY start_ts) - sum as next_consumption
  FROM statistics
  WHERE metadata_id = (SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.east')
),
consumption_with_avg AS (
  -- Step 2: Calculate rolling average
  SELECT 
    period,
    state,
    sum,
    consumption,
    next_consumption,
    AVG(consumption) OVER (
      ORDER BY start_ts
      ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING
    ) as avg_consumption
  FROM consumption_calc
)
SELECT 
  period,
  state,
  sum,
  ROUND(consumption, 2) as this_period_consumption,
  ROUND(next_consumption, 2) as next_period_consumption,
  ROUND(avg_consumption, 2) as baseline_avg,
  CASE 
    WHEN consumption > avg_consumption * 5 
         AND next_consumption < 0 
         AND ABS(next_consumption) > avg_consumption * 3
    THEN '❌ SPIKE + DROP GLITCH DETECTED'
    WHEN consumption > avg_consumption * 5 
         AND next_consumption < avg_consumption * 0.2
    THEN '⚠️ SPIKE followed by very low consumption'
    WHEN consumption < 0 
         AND next_consumption > avg_consumption * 3
    THEN '⚠️ DROP followed by spike (inverse glitch)'
    ELSE 'Potential issue'
  END as glitch_pattern,
  'Data integrity compromised - manual correction may be needed' as recommendation
FROM consumption_with_avg
WHERE avg_consumption > 0
  AND (
    -- Spike followed by negative consumption
    (consumption > avg_consumption * 5 AND next_consumption < 0) OR
    -- Negative consumption followed by spike
    (consumption < 0 AND next_consumption > avg_consumption * 3) OR
    -- Extreme spike followed by near-zero
    (consumption > avg_consumption * 10 AND next_consumption < avg_consumption * 0.2)
  )
ORDER BY period DESC
LIMIT 50;
```
