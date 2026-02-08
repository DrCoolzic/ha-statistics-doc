SELECT 
    sm.entity_id,
    s.state,
    -- datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    datetime(COALESCE(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed,
    JSON_EXTRACT(sa.shared_attrs, '$.unit_of_measurement') as unit_of_measurement
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'sensor.linky_easf01' AND 
  (
--     s.last_updated_ts BETWEEN 
--     strftime('%s', '2026-02-07 23:20:00', 'utc') 
--     AND strftime('%s', '2026-02-07 23:30:00', 'utc')
--   OR 
    s.last_updated_ts BETWEEN 
      strftime('%s', '2026-02-08 08:55:00', 'utc') 
      AND strftime('%s', '2026-02-08 09:03:00', 'utc')
)
ORDER BY s.last_updated_ts ASC;



SELECT 
    sm.statistic_id,
    datetime(s.start_ts, 'unixepoch', 'localtime') as period_start,
    -- datetime(s.created_ts, 'unixepoch', 'localtime') as created_at,
    s.state,
    s.sum
FROM statistics_short_term s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.linky_easf01' 
  AND (
    -- (datetime(s.start_ts, 'unixepoch', 'localtime') >= '2026-02-07 23:04:00'
    --  AND datetime(s.start_ts, 'unixepoch', 'localtime') < '2026-02-07 23:41:00')
    -- OR
    (datetime(s.start_ts, 'unixepoch', 'localtime') >= '2026-02-08 08:49:00'
     AND datetime(s.start_ts, 'unixepoch', 'localtime') < '2026-02-08 09:11:00')
     )
ORDER BY s.start_ts ASC;