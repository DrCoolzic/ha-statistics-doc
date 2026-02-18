# Unpredictable/Incomprehensible unit changes in statistics

## Test Sensor description

We have an ESPHome integration with an energy sensor (linky_east) that returns values in Wh.

in core.entity_registry the sensor is described like this in the entities section:

```json
{
  "aliases": [],
  "area_id": null,
  "categories": {},
  "capabilities": {
    "state_class": "total_increasing"
  },
  "config_entry_id": "01KHP2FH8BS5G3H5GQ720Q0YTD",
  "config_subentry_id": null,
  "created_at": "2024-11-18T13:35:48.028338+00:00",
  "device_class": null,
  "device_id": "4442b4ca97a23c29c59787f58ef1f683",
  "disabled_by": null,
  "entity_category": null,
  "entity_id": "sensor.linky_east",
  "hidden_by": null,
  "icon": null,
  "id": "168ad5d1e26d02fe707a1522fccd3bb9",
  "has_entity_name": true,
  "labels": [],
  "modified_at": "2026-02-17T15:35:51.249888+00:00",
  "name": null,
  "options": {
    "conversation": {
      "should_expose": false
    },
    "sensor": {
      "unit_of_measurement": "Wh",
      "display_precision": null,
      "suggested_display_precision": 0
    }
  },
  "original_device_class": "energy",
  "original_icon": "mdi:flash",
  "original_name": "linky_east",
  "platform": "esphome",
  "suggested_object_id": null,
  "supported_features": 0,
  "translation_key": null,
  "unique_id": "C4:5B:BE:54:8B:C7-sensor-linky_east",
  "previous_unique_id": null,
  "unit_of_measurement": "Wh"
}
```

We can see that the unit of measurement is Wh as well as the unit of measurement in the options.

## Starting test clean by removing the sensor integration

To start fresh for the test we delete the ESPHome integration.

### Entity registry

This moves the sensor description from the entity_registry from entities section to deleted_entities section. With the following description:

```json
{
  "aliases":[],
  "area_id":null,
  ...
  "options": {
    "conversation": {
      "should_expose": false
    },
    "sensor": {
      "unit_of_measurement": "Wh",
      "display_precision": null,
      "suggested_display_precision": 0
    }
  },
  "options_undefined": false,
  "orphaned_timestamp": 1771415872.6526582,
  "platform": "esphome",
  "unique_id": "C4:5B:BE:54:8B:C7-sensor-linky_east"
}
```

We can see that the unit of measurement is gone but one in the options is still there. Note also that the entities has been orphaned.
We now remove all statistics for the sensor from the statistics tables (statistics_meta, statistics, and statistics_short_term) using the fix in dev tools_> statistics.

## Adding the integration again makes the sensor available again

### Retrieve energy sensor information from states table

```sql
SELECT 
    sm.entity_id, 
    s.state,
    JSON_EXTRACT(sa.shared_attrs, '$.unit_of_measurement') as unit,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    datetime(COALESCE(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'sensor.linky_east'
ORDER BY s.last_updated_ts DESC;
```

entity_id | state | unit | last_updated | last_changed
--- | --- | --- | --- | ---
sensor.linky_east | 73369832 | Wh | 2/18/2026 13:17 | 2/18/2026 13:17
sensor.linky_east | 73369784 | Wh | 2/18/2026 13:16 | 2/18/2026 13:16
sensor.linky_east | 73369728 | Wh | 2/18/2026 13:15 | 2/18/2026 13:15
sensor.linky_east | 73369680 | Wh | 2/18/2026 13:15 | 2/18/2026 13:15
sensor.linky_east | unknown | Wh | 2/18/2026 13:15 | 2/18/2026 13:15
sensor.linky_east |  |  | 2/18/2026 12:57 | 2/18/2026 12:57
sensor.linky_east | unavailable | Wh | 2/18/2026 12:57 | 2/18/2026 12:57
sensor.linky_east | 73368504 | Wh | 2/18/2026 12:57 | 2/18/2026 12:57
sensor.linky_east | 73368416 | Wh | 2/18/2026 12:56 | 2/18/2026 12:56
sensor.linky_east | 73368336 | Wh | 2/18/2026 12:55 | 2/18/2026 12:55

We can see that at 12:57 the sensor was unavailable because we removed the integration. After adding the integration again @ 13:15 the sensor was available again. Here the unit of measurement and the values are correct.

### Retrieve energy sensor information from statistics_short_term table

We have to wait for the statistics info to be added to the statistics_short_term table.

```sql
SELECT 
    sm.statistic_id,
    datetime(s.start_ts, 'unixepoch', 'localtime') as period_start,
    datetime(s.created_ts, 'unixepoch', 'localtime') as created_at,
    s.state,
    s.sum,
    s.sum - LAG(s.sum) OVER (ORDER BY s.start_ts) as period_delta,
    sm.unit_of_measurement
FROM statistics_short_term s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.linky_east'
ORDER BY s.start_ts DESC;
```

statistic_id | period_start | created_at | state | sum | period_delta |  unit_of_measurement
--- | --- | --- | --- | --- | --- | ---
sensor.linky_east | 2/18/2026 13:35 | 2/18/2026 13:40 | 73370848 | 1168 | 224 | Wh
sensor.linky_east | 2/18/2026 13:30 | 2/18/2026 13:35 | 73370624 | 944 | 232 | Wh
sensor.linky_east | 2/18/2026 13:25 | 2/18/2026 13:30 | 73370392 | 712 | 224 | Wh
sensor.linky_east | 2/18/2026 13:20 | 2/18/2026 13:25 | 73370168 | 488 | 240 | Wh
sensor.linky_east | 2/18/2026 13:15 | 2/18/2026 13:20 | 73369928 | 248 |  | Wh

Information in statistics_short_term is correct with correct unit of measurement and values.

### Retrieve energy sensor information from statistics table

We have to wait much longer for the statistics info to be added to the statistics table.

```sql
SELECT 
    sm.statistic_id,
    datetime(s.start_ts, 'unixepoch', 'localtime') as period_start,
    datetime(s.created_ts, 'unixepoch', 'localtime') as created_at,
    s.state,
    s.sum,
    s.sum - LAG(s.sum) OVER (ORDER BY s.start_ts) as period_delta,
    sm.unit_of_measurement
FROM statistics s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.linky_east'
ORDER BY s.start_ts DESC;
```

statistic_id | period_start | created_at | state | sum | period_delta | unit_of_measurement
--- | --- | --- | --- | --- | --- | ---
sensor.linky_east | 2/18/2026 13:00 | 2/18/2026 14:00 | 73371792 | 2112 |  | Wh

### Retrieve energy sensor information from entity registry

```json
{
  "aliases": [],
  "area_id": null,
  ...
  "options": {
    "conversation": {
      "should_expose": false
    },
    "sensor": {
      "unit_of_measurement": "Wh",
      "display_precision": null,
      "suggested_display_precision": 0
    }
  },
 ...
  "previous_unique_id": null,
  "unit_of_measurement": "Wh"
}
```

We can see that the unit of measurement is here again in Wh as well as in the options.
