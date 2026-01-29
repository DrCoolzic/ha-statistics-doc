-- rertreive state changes for an entity within a specific time range -- MySQL version
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

-- retrieve state changes for an entity within a specific time range -- SQLite version
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    --datetime(COALESCE(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed
    datetime(IFNULL(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed,
    datetime(s.last_reported_ts, 'unixepoch', 'localtime') as last_reported
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
WHERE sm.entity_id = 'sensor.linky_sinsts'
  AND s.last_updated_ts BETWEEN 
    strftime('%s', '2026-01-27 12:00:00') 
    AND strftime('%s', '2026-01-27 13:00:00')
ORDER BY s.last_updated_ts;