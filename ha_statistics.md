# Understanding and Using Home Assistant Statistics

## Overview

This document explains how statistics are generated in Home Assistant (HA) and how to work with them effectively. Statistics provide aggregated, long-term data storage that is more efficient than raw state history, making them essential for tracking trends, creating dashboards, and analyzing system behavior over time.

Before diving into statistics themselves, we'll explore how HA Core and the Recorder integration work, as these form the foundation for statistics generation.

---

## Part 1: Foundational Concepts

### 1.1 Simplified Home Assistant Core Behavior

Home Assistant Core is an **event-driven application** that maintains real-time state for all entities in your system. Understanding this architecture is crucial to understanding how statistics are derived.

#### Key Concepts

**Entities and States**

An IoT device or service is represented as one or more entities in Home Assistant. Each entity has a current state with associated attributes. For example:

- Entity: `light.kitchen`
- State: `on`
- Attributes: color, brightness, etc.

**Events**

Everything that happens in HA is represented as an event:

- A light being turned on
- A motion sensor being triggered
- An automation executing
- A state change occurring

**State Update Frequency**

The frequency of state updates varies by integration:

- **Polling integrations**: Update at regular intervals (e.g., every 30 seconds for a temperature sensor)
- **Push-based integrations**: Update when the device reports a change (e.g., a ZigBee sensor waking from sleep)
- **Event-based integrations**: Update immediately when triggered (e.g., a button press)

**Stateless Operation**

HA Core can run without persistent history. In this mode, you always know the current state of your system, but not how you arrived there. The Recorder integration provides this historical context.

> **Further Reading**: For more details, see the [Core Architecture](https://developers.home-assistant.io/docs/architecture_index) and [Entity Integration](https://developers.home-assistant.io/docs/core/entity) documentation.

---

### 1.2 The Recorder Integration

The Recorder integration stores historical data about your system in a database, enabling you to track how states change over time.

#### How Recording Works

**Sampling and Storage**

- Objects are **sampled every 5 seconds** by default (configurable)
- Values are **committed to the database only if they have changed**
- This 5-second interval is a balance between responsiveness and storage efficiency

**Why 5 Seconds?**
According to the Nyquist-Shannon sampling theorem, a 5-second sampling rate means no events are lost if they occur at intervals of **10 seconds or longer**. This covers the vast majority of entity updates while preventing database saturation during event bursts.

**Database Backend**

- **Default**: SQLite (suitable for most installations)
- **Alternatives**: PostgreSQL, MySQL/MariaDB (for advanced setups with high write volumes)

> **Further Reading**: See the [Database Schema documentation](https://developers.home-assistant.io/docs/architecture/database) for complete table descriptions.

---

### 1.3 The States Table

The `states` table is the primary storage location for entity state history. Understanding its structure is essential for working with raw data and statistics.

#### Table Schema


| Field                   | Type         | Description                                                                           |
| ------------------------- | -------------- | --------------------------------------------------------------------------------------- |
| `state_id`              | INTEGER      | Primary key, auto-incrementing unique identifier for each state record                |
| `metadata_id`           | INTEGER      | Foreign key to`states_meta` table (contains `entity_id` mapping)                      |
| `state`                 | VARCHAR(255) | The actual state value (e.g., "234.0", "on", "off", "23.5°C")                        |
| `last_updated_ts`       | FLOAT        | Unix timestamp when state was last updated (even if only attributes changed)          |
| `last_changed_ts`       | FLOAT        | Unix timestamp when the actual state value changed (NULL if same as`last_updated_ts`) |
| `last_reported_ts`      | FLOAT        | Unix timestamp when the state was last reported by the integration                    |
| `old_state_id`          | INTEGER      | Links to the previous`state_id` for this entity (enables state history traversal)     |
| `attributes_id`         | INTEGER      | Foreign key to`state_attributes` table (stored separately to avoid duplication)       |
| `context_id_bin`        | BLOB(16)     | Binary UUID identifying the context that caused this state change                     |
| `context_user_id_bin`   | BLOB(16)     | Binary UUID of the user who initiated the change (if applicable)                      |
| `context_parent_id_bin` | BLOB(16)     | Binary UUID of the parent context (for automation chains)                             |
| `origin_idx`            | SMALLINT     | Index indicating the origin of the state change                                       |

#### Deprecated Fields (Still Present for Migration)


| Field               | Replacement                     | Notes                                          |
| --------------------- | --------------------------------- | ------------------------------------------------ |
| `entity_id`         | `states_meta.entity_id`         | Normalized to avoid repetition                 |
| `attributes`        | `state_attributes.shared_attrs` | Normalized to reduce storage                   |
| `last_changed`      | `last_changed_ts`               | Converted to timestamp format                  |
| `last_updated`      | `last_updated_ts`               | Converted to timestamp format                  |
| `event_id`          | N/A                             | State changes no longer stored in events table |
| `context_id`        | `context_id_bin`                | Converted to binary format                     |
| `context_user_id`   | `context_user_id_bin`           | Converted to binary format                     |
| `context_parent_id` | `context_parent_id_bin`         | Converted to binary format                     |

#### Important Distinctions

- **`last_updated_ts`**: Changes when state OR attributes change
- **`last_changed_ts`**: Changes only when the state value itself changes.  The `last_changed_ts` field is stored as NULL when it equals `last_updated_ts` to save database space
- **`last_reported_ts`**: The timestamp from the integration/device

Among all the entities found in the status table, the ones that interest us are the entities that are considered statistics. We will look at the definition criteria for statistical entities in more detail, but we can already say that there are two main types: the **measurement** type and the **metered** type.

Lets first take the example an integration that poll the apparent power of a house every minute. We use the following query:

```sqlite
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    datetime(COALESCE(s.last_changed_ts, s.last_updated_ts), 'unixepoch', 'localtime') as last_changed,
    datetime(s.last_reported_ts, 'unixepoch', 'localtime') as last_reported
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
WHERE sm.entity_id = 'sensor.linky_sinsts' 
AND s.last_updated_ts BETWEEN 
    strftime('%s', '2026-01-27 11:59:00') 
    AND strftime('%s', '2026-01-27 13:01:00')
ORDER BY s.last_updated_ts;
```

| entity_id           | state | last_updated    | last_changed    | last_reported   |
| ------------------- | ----- | --------------- | --------------- | --------------- |
| sensor.linky_sinsts | 2039  | 1/27/2026 12:59 | 1/27/2026 12:59 | 1/27/2026 12:59 |
| sensor.linky_sinsts | 2040  | 1/27/2026 13:00 | 1/27/2026 13:00 | 1/27/2026 13:00 |
| sensor.linky_sinsts | 2030  | 1/27/2026 13:01 | 1/27/2026 13:01 | 1/27/2026 13:01 |
| ...                 | ...   | ...             | ...             | ...             |
| sensor.linky_sinsts | 1825  | 1/27/2026 13:58 | 1/27/2026 13:58 | 1/27/2026 13:58 |
| sensor.linky_sinsts | 1827  | 1/27/2026 13:59 | 1/27/2026 13:59 | 1/27/2026 13:59 |
| sensor.linky_sinsts | 1820  | 1/27/2026 14:00 | 1/27/2026 14:00 | 1/27/2026 14:00 |

Here we can see that we get a value every minutes.

This is quite different from a ZigBee temperature sensor that reports value at a pace fixed by the device

| entity_id                 | state | last_updated  | last_changed  | last_reported |
| ------------------------- | ----- | ------------- | ------------- | ------------- |
| sensor.family_temperature | 13.59 | 1/27/26 12:00 | 1/27/26 12:00 | 1/27/26 12:00 |
| sensor.family_temperature | 13.63 | 1/27/26 12:01 | 1/27/26 12:01 | 1/27/26 12:01 |
| sensor.family_temperature | 13.6  | 1/27/26 12:38 | 1/27/26 12:38 | 1/27/26 12:38 |
| sensor.family_temperature | 13.64 | 1/27/26 12:51 | 1/27/26 12:51 | 1/27/26 12:51 |

The two devices presented above are of type measurement (e.g. temperature)  where values goes up and down.
We also have devices of type metered (e.g. energy consumption) where the return values are increasing.

| entity_id         | state    | last_updated    | last_changed    | last_reported   |
| ----------------- | -------- | --------------- | --------------- | --------------- |
| sensor.linky_east | 72199456 | 1/27/2026 12:59 | 1/27/2026 12:59 | 1/27/2026 12:59 |
| sensor.linky_east | 72199488 | 1/27/2026 13:00 | 1/27/2026 13:00 | 1/27/2026 13:00 |
| sensor.linky_east | 72199520 | 1/27/2026 13:01 | 1/27/2026 13:01 | 1/27/2026 13:01 |
| ...               | ...      | ...             | ...             | ...             |
| sensor.linky_east | 72201168 | 1/27/2026 13:58 | 1/27/2026 13:58 | 1/27/2026 13:58 |
| sensor.linky_east | 72201200 | 1/27/2026 13:59 | 1/27/2026 13:59 | 1/27/2026 13:59 |
| sensor.linky_east | 72201224 | 1/27/2026 14:00 | 1/27/2026 14:00 | 1/27/2026 14:00 |



## Part 2: Statistics Generation

### 2.1 What Are Statistics?

Statistics are **aggregated, compressed representations** of entity data over time. Unlike the `states` table which stores every state change, the `statistics` table stores:

- **Short-term statistics**: 5-minute intervals (retained for 10 days by default)
- **Long-term statistics**: 1-hour intervals (retained indefinitely by default)

This dramatically reduces storage requirements while preserving trend data.

### 2.2 Which Entities Generate Statistics?

Statistics are automatically generated for **any entity** that meets ALL of these criteria:

1. **Has a `state_class` property** with value:
   - `measurement` (values that fluctuate)
   - `total` (cumulative counter)
   - `total_increasing` (cumulative counter that only increases)
2. **Has numerical state values**
3. **Has a `unit_of_measurement` property**

The `state_class` attribute determines how statistics are calculated:


| State Class        | Description                            | Example                                  |
| ------------------ | -------------------------------------- | ---------------------------------------- |
| `measurement`      | Value can go up or down                | Temperature, humidity, power consumption |
| `total`            | Monotonically increasing counter       | Total kWh consumed, total water used     |
| `total_increasing` | Same as`total`, but resets are handled | Smart meter readings that might reset    |

There are two categories of statistics: the **measurement** type and the **metered** type

1. The *measurement* entities do not represent a total amount. Their `state_class` property must be set to `measurement`, and the `device_class` must **not** be either of `date`, `enum`, `energy`, `gas`, `monetary`, `timestamp`, `volume` or `water`. In this case Home Assistant tracks the **min**, **max** and **mean** values during the statistics period. A typical usage is the measurement of temperature.
2. The *metered* entities represents a total amount. Their `state_class` property must be equal to either `total` or `total_increasing`. In this case Home Assistant tracks the **state**, **sum** and **last_reset** values during the statistics period. Typical usage is for tracking a total amount value that may optionally reset periodically, like this month's energy consumption, today's energy production, the weight of pellets used to heat the house over the last week or the yearly growth of a stock portfolio. When `state_class` is  `total` the usage of `last_reset` allows to track increasing or decreasing state like a stock portfolio (even though we would prefer that it always increase) .

[TODO check if information correct - Add here or in section 1.3 example of different state table for meter type and subtype]

> For detail information read [sensor developer documentation](https://developers.home-assistant.io/docs/core/entity/sensor#long-term-statistics) and [Long- and short-term statistics](https://data.home-assistant.io/docs/statistics)

### 2.3 Statistics Generation Process

Home Assistant provides support to process the *statistics entities*. 

1. **Entity state changes** are recorded in the `states` table to keeps track of supported entities and different elements of the entity state. 

2. **Every 5 minutes**:

   - it processes the statistics entities in the state table and perform some calculation.

   - statistics information are written to `statistics_short_term` table according to the category of the statistic:
     - For `measurement`: mean, min, max are saved
   
     - For `total`: sum and state are saved
   
3. **Every 60 minutes**, short-term stats are aggregated into hourly long-term statistics

## Part 3: The Statistics Tables

TODO

The statistics are stored in the `statistics` and `statistics_short_term` tables with this basic structure:

**Key Fields:**

- `metadata_id`: Links to entity
- `start_ts`: Start of the time interval
- `mean`: Average value during the interval
- `min`: Minimum value
- `max`: Maximum value
- `sum`: Cumulative sum (for `total` state class)
- `state`: Last known state in the interval


---

## Part 3: Working with Statistics

### 3.1 Benefits of Statistics

- **Reduced storage**: Hourly aggregates vs. potentially hundreds of state changes
- **Faster queries**: Pre-aggregated data loads much faster
- **Long-term retention**: Keep years of trend data without massive databases
- **Energy dashboard**: Powers the built-in energy monitoring features

### 3.2 Accessing Statistics

**Via the UI:**

- Developer Tools → Statistics
- Energy Dashboard (for energy entities)
- History graphs automatically use statistics for long time ranges

**Via Services:**

- `recorder.import_statistics`: Import external statistics
- `recorder.adjust_sum`: Correct cumulative values (e.g., after meter replacement)

**Via Database:**

- Direct SQL queries to `statistics` and `statistics_short_term` tables
- Useful for advanced analysis and custom integrations

### 3.3 Common Use Cases

**Energy Monitoring**
Track total energy consumption with `total_increasing` state class, automatically handling meter resets.

**Temperature Trends**
Use `measurement` state class to track min/max/average temperatures over months or years.

**Cost Tracking**
Combine consumption statistics with pricing data to calculate costs.

**Performance Analysis**
Identify patterns in system behavior over extended periods.

---

## Part 4: Best Practices and Troubleshooting

### 4.1 Configuration Recommendations

**Purge Settings**
Adjust recorder purge settings based on your storage capacity:

```yaml
recorder:
  purge_keep_days: 7  # Keep detailed states for 7 days
  commit_interval: 1  # Commit to DB every second (higher load, less data loss risk)
```

**Include/Exclude Entities**
Only record what you need:

```yaml
recorder:
  exclude:
    domains:
      - automation
      - script
    entity_globs:
      - sensor.temp_*_battery
```

### 4.2 Statistics Limitations

- **No retroactive generation**: Statistics are only generated going forward
- **Missing data handling**: Gaps in state data create gaps in statistics
- **State class changes**: Changing state class doesn't recalculate existing statistics
- **Precision**: Aggregation inherently loses detail compared to raw states

### 4.3 Troubleshooting

**Missing Statistics**

- Verify entity has `state_class` attribute
- Check entity provides numerical values
- Ensure recorder is including the entity
- Check Developer Tools → Statistics for errors

**Incorrect Values**

- Use `recorder.adjust_sum` service to fix cumulative totals
- Check for unit conversions in entity attributes
- Verify state changes are being recorded in `states` table

**Performance Issues**

- Reduce `purge_keep_days` to limit database size
- Consider migrating to PostgreSQL for large installations
- Exclude unnecessary entities from recording

---

## Conclusion

Statistics in Home Assistant provide an efficient way to store and analyze long-term trends while managing storage constraints. By understanding the relationship between states, the recorder, and statistics generation, you can make informed decisions about what to track and how to optimize your system's performance.

The key takeaways:

1. States capture every change; statistics aggregate them efficiently
2. State class determines how statistics are calculated
3. Short-term and long-term statistics balance detail with storage
4. Proper configuration prevents both storage bloat and data loss

---

## Additional Resources

- [Home Assistant Recorder Documentation](https://www.home-assistant.io/integrations/recorder/)
- [Statistics Integration](https://www.home-assistant.io/integrations/analytics/)
- [Database Schema Reference](https://developers.home-assistant.io/docs/architecture/database)
- [Energy Dashboard Guide](https://www.home-assistant.io/docs/energy/)
