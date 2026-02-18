# Fixing imported counter discontinuity (SQLite)

This guide applies to `total` / `total_increasing` statistics where an import causes the long-term `sum` to jump backwards (creating a large negative delta).

## What happened (why the gap came back)

- Home Assistant builds **long-term** rows (`statistics`, 1h) from **short-term** rows (`statistics_short_term`, 5min).
- If you only fix `statistics` but leave `statistics_short_term` unchanged, then when HA generates the next hourly row, it will use the **unfixed** short-term baseline and the discontinuity will reappear.

So the durable fix is:

1. Fix **short-term** sums from the break point onward.
2. Fix **long-term** sums from the break point onward.
3. Restart Home Assistant.
4. Optionally, adjust the single “break hour” to avoid a `0` delta (estimation).

## Before you start

- Make a backup copy of the database.
- Stop Home Assistant (recommended) so it does not write new statistics while you edit.

## Step 1 — Identify the break point and compute the offset (long-term)

This finds the most negative jump and returns the break timestamp and the constant offset to add:

```sql
WITH ordered AS (
  SELECT
    s.start_ts,
    datetime(s.start_ts, 'unixepoch', 'localtime') AS period_start,
    s.sum,
    LAG(s.sum) OVER (ORDER BY s.start_ts) AS prev_sum,
    s.sum - LAG(s.sum) OVER (ORDER BY s.start_ts) AS delta_sum
  FROM statistics s
  JOIN statistics_meta sm ON sm.id = s.metadata_id
  WHERE sm.statistic_id = 'sensor.linky_east'
    AND s.sum IS NOT NULL
)
SELECT
  period_start,
  start_ts AS break_ts,
  prev_sum,
  sum AS break_sum,
  delta_sum,
  (prev_sum - sum) AS offset_to_add
FROM ordered
WHERE delta_sum < 0
ORDER BY delta_sum ASC
LIMIT 1;
```

Record:

- `break_ts`
- `offset_to_add`

## Step 2 — Apply the baseline shift to short-term (durable fix)

Run this first.

### Option A (recommended) — Auto-detect break + compute offset + update (one statement)

This statement detects the most negative jump in the **long-term** table (`statistics`), computes the constant offset, and applies it to **short-term** sums from that break point onward.

```sql
WITH
meta AS (
  SELECT id AS metadata_id
  FROM statistics_meta
  WHERE statistic_id = 'sensor.linky_east'
),
ordered AS (
  SELECT
    s.start_ts,
    s.sum,
    LAG(s.sum) OVER (ORDER BY s.start_ts) AS prev_sum,
    s.sum - LAG(s.sum) OVER (ORDER BY s.start_ts) AS delta_sum
  FROM statistics s
  JOIN meta ON s.metadata_id = meta.metadata_id
  WHERE s.sum IS NOT NULL
),
break AS (
  SELECT
    start_ts AS break_ts,
    (prev_sum - sum) AS offset_to_add
  FROM ordered
  WHERE delta_sum < 0
  ORDER BY delta_sum ASC
  LIMIT 1
)
UPDATE statistics_short_term
SET sum = sum + (SELECT offset_to_add FROM break)
WHERE metadata_id = (SELECT metadata_id FROM meta)
  AND sum IS NOT NULL
  AND start_ts >= (SELECT break_ts FROM break);
```

### Option B — Manual (if you already know `break_ts` and `offset_to_add`)

```sql
WITH
meta AS (
  SELECT id AS metadata_id
  FROM statistics_meta
  WHERE statistic_id = 'sensor.linky_east'
)
UPDATE statistics_short_term
SET sum = sum + 40193156
WHERE metadata_id = (SELECT metadata_id FROM meta)
  AND sum IS NOT NULL
  AND start_ts >= strftime('%s', '2026-02-14 14:00:00');
```

Replace:

- `40193156` with your `offset_to_add`
- `'2026-02-14 14:00:00'` with your break hour

## Step 3 — Apply the baseline shift to long-term

Run this after Step 2.

### Option A (recommended) — Auto-detect break + compute offset + update (one statement)

```sql
WITH
meta AS (
  SELECT id AS metadata_id
  FROM statistics_meta
  WHERE statistic_id = 'sensor.linky_east'
),
ordered AS (
  SELECT
    s.start_ts,
    s.sum,
    LAG(s.sum) OVER (ORDER BY s.start_ts) AS prev_sum,
    s.sum - LAG(s.sum) OVER (ORDER BY s.start_ts) AS delta_sum
  FROM statistics s
  JOIN meta ON s.metadata_id = meta.metadata_id
  WHERE s.sum IS NOT NULL
),
break AS (
  SELECT
    start_ts AS break_ts,
    (prev_sum - sum) AS offset_to_add
  FROM ordered
  WHERE delta_sum < 0
  ORDER BY delta_sum ASC
  LIMIT 1
)
UPDATE statistics
SET sum = sum + (SELECT offset_to_add FROM break)
WHERE metadata_id = (SELECT metadata_id FROM meta)
  AND sum IS NOT NULL
  AND start_ts >= (SELECT break_ts FROM break);
```

### Option B — Manual (if you already know `break_ts` and `offset_to_add`)

```sql
WITH
meta AS (
  SELECT id AS metadata_id
  FROM statistics_meta
  WHERE statistic_id = 'sensor.linky_east'
)
UPDATE statistics
SET sum = sum + 40193156
WHERE metadata_id = (SELECT metadata_id FROM meta)
  AND sum IS NOT NULL
  AND start_ts >= strftime('%s', '2026-02-14 14:00:00');
```

Same replacements as Step 2.

## Step 4 — Start Home Assistant and verify

- Start Home Assistant.
- Verify that new hourly rows keep increasing and deltas are positive.

Useful verification query (short-term):

```sql
SELECT
  sm.statistic_id,
  datetime(s.start_ts, 'unixepoch', 'localtime') AS period_start,
  s.sum,
  s.sum - LAG(s.sum) OVER (ORDER BY s.start_ts) AS period_delta
FROM statistics_short_term s
JOIN statistics_meta sm ON sm.id = s.metadata_id
WHERE sm.statistic_id = 'sensor.linky_east'
ORDER BY s.start_ts DESC
LIMIT 50;
```

## Step 5 (optional) — Replace the `0` delta in the break hour with an estimate

Note: not a good idea

After Step 3, the break hour often becomes `0` because continuity was forced. If you prefer an estimated value, this single statement:

- Computes `estimated_delta = (delta_before + delta_after) / 2`
- Adds it to `sum` at the break hour and all later rows (so later deltas remain unchanged)

```sql
WITH
meta AS (
  SELECT id AS metadata_id
  FROM statistics_meta
  WHERE statistic_id = 'sensor.linky_east'
),
ordered AS (
  SELECT
    s.start_ts,
    s.sum,
    LAG(s.sum, 1) OVER (ORDER BY s.start_ts)  AS prev_sum,
    LAG(s.sum, 2) OVER (ORDER BY s.start_ts)  AS prev2_sum,
    LEAD(s.sum, 1) OVER (ORDER BY s.start_ts) AS next_sum
  FROM statistics s
  JOIN meta ON s.metadata_id = meta.metadata_id
  WHERE s.sum IS NOT NULL
),
params AS (
  SELECT
    start_ts AS break_ts,
    ((prev_sum - prev2_sum) + (next_sum - sum)) / 2.0 AS estimated_delta
  FROM ordered
  WHERE start_ts = strftime('%s', '2026-02-14 14:00:00')
)
UPDATE statistics
SET sum = sum + (SELECT estimated_delta FROM params)
WHERE metadata_id = (SELECT metadata_id FROM meta)
  AND sum IS NOT NULL
  AND start_ts >= (SELECT break_ts FROM params);
```

## If you already applied partial fixes and the gap moved

If you see a new negative jump at a later hour (e.g. at 17:00), it means HA generated new hourly rows using an unfixed baseline.

Best option:

- Restore your database backup and apply the steps above in order.

If you cannot restore:

- Apply Step 2 (short-term shift) using the original break/offset.
- Then re-run Step 1 to find the new long-term break and apply Step 3 again for the new break point.
