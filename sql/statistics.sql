-- retreive statistics for a measurement entity within a specific time range -- MySQL version
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

-- retrieve statistics for a measurement entity within a specific time range -- SQLite version
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


-- SQL retrieve statistics for a total entity within a specific time range -- SQLite version
SELECT 
    sm.statistic_id,
    datetime(s.start_ts, 'unixepoch', 'localtime') as period_start,
    datetime(s.created_ts, 'unixepoch', 'localtime') as created_at,
    s.state,
    s.sum,
    datetime(s.last_reset_ts, 'unixepoch', 'localtime') as last_reset
FROM statistics_short_term s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.linky_east'
  AND datetime(s.start_ts, 'unixepoch', 'localtime') >= '2026-01-27 13:00:00'
  AND datetime(s.start_ts, 'unixepoch', 'localtime') < '2026-01-27 14:00:00'
ORDER BY s.start_ts ASC;
