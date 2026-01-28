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

Entities are the basic building blocks to hold data in Home Assistant. An entity represents a sensor, actor, or function in Home Assistant. Entities are used to monitor physical properties or to control other entities. An entity is usually part of a device or a service.  Entities constantly keep track of their state and associated attributes. For example:

- Entity: `light.kitchen`
- State: `on`
- Attributes: color, brightness, etc.

**Events**

Everything that happens in HA is represented as an event:

- A light being turned on
- A motion sensor being triggered
- An automation executing
- A state change occurring

Note that all entities produce state change events. Every time a state changes, a state change event is produced. State change events are just one type of event on the event bus, but there are other kinds of events, such as the [built-in events](https://www.home-assistant.io/docs/configuration/events/#built-in-events-core) that are used to coordinate between various integrations.

**State Update Frequency**

The frequency of state updates varies by integration:

- **Polling integrations**: Update at regular intervals (e.g., every 30 seconds for a temperature sensor)
- **Push-based integrations**: Update when the device reports a change (e.g., a ZigBee temperature sensor waking from sleep)
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

> **Further Reading**: See the [Database Schema documentation](https://www.home-assistant.io/docs/backend/database/#schema) for complete table descriptions.

---

### 1.3 The States Table

The Recorder Integration writes numerous tables from the database, but in the context of this document, the table we are interested in is the `state` table that is the primary storage location for entity state history. Understanding its structure is essential for working with raw data and statistics.

#### Used Fields

| Field                   | Type         | Description                                                                           |
| ----------------------- | ------------ | ------------------------------------------------------------------------------------- |
| `state_id`              | INTEGER      | Primary key, auto-incrementing unique identifier for each state record                |
| `metadata_id`           | INTEGER      | Foreign key to`states_meta` table (contains `entity_id` mapping)                      |
| `state`                 | VARCHAR(255) | The actual state value (e.g., "234.0", "on", "off", "23.5°C")                         |
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
| ------------------- | ------------------------------- | ---------------------------------------------- |
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

Among all the entities found in the status table, in this document we focus on statistical entities. We will look at the detail definition of a statistical entities in more detail, but we will see that they belong to two categories: the **measurement** category and the **total** category.

Lets take a first example an integration that poll the apparent power of a house every minute. We use the following query to select the state entries of a specific entity in a specified date range.

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

Here we can see that we have a new state entry every minutes.

This is quite different from a ZigBee temperature sensor that reports value at a pace fixed by the device

| entity_id                 | state | last_updated  | last_changed  | last_reported |
| ------------------------- | ----- | ------------- | ------------- | ------------- |
| sensor.family_temperature | 13.59 | 1/27/26 12:00 | 1/27/26 12:00 | 1/27/26 12:00 |
| sensor.family_temperature | 13.63 | 1/27/26 12:01 | 1/27/26 12:01 | 1/27/26 12:01 |
| sensor.family_temperature | 13.6  | 1/27/26 12:38 | 1/27/26 12:38 | 1/27/26 12:38 |
| sensor.family_temperature | 13.64 | 1/27/26 12:51 | 1/27/26 12:51 | 1/27/26 12:51 |

The two entities presented above belong to the category measurement (e.g. temperature)  where the state values goes up and down.
We also have entities of that belongs to the category metered (e.g. energy consumption) where the state values are monotonically increasing.

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

Home Assistant supports statistics, which are **aggregated and compressed representations** of entity data over time. Unlike the *states* table, which stores every state change, the *short-term statistics* table stores information every 5 minutes, and the *long-term statistics* table stores information once every hour. This dramatically reduces storage requirements while preserving trend data.

### 2.2 Which Entities Generate Statistics?

Statistics are automatically generated for **entities** that meet certain criteria that we will detail. They can be classified into two categories: *statistical measurement entities* and *statistical counter entities*. Note that all statistical entities belong to sensor integration.

#### 2.2.1 Measurement Statistics representing a measurement

Their `state_class` property must be set to `measurement` or `measurement_angle` and the `device_class` must not be either of `date`, `enum`, `energy`, `gas`, `monetary`, `timestamp`, `volume` or `water`. Usually their `unit_of_measurement` property is also defined. In this case Home Assistant tracks the **state**, **min**, **max** and **mean** values during the statistics period and update them every 5 minutes.

The `state` of "*measurement statistics*" represents a **real-time measurement**, such as current temperature, humidity, or electrical power. Their sate should not be a historical aggregation such as statistics or forecasts for the future. For example, tomorrow's forecast temperature, yesterday's energy consumption, or any other data that does not include a *current measurement* should not be marked as a measurement. The statistical `measurement_angle` entities are similar with the above but in this case the sate represent represents a real-time measurement for angles measured in degrees such as current wind direction.

Note that contrary to the next category these statistics do not represent a total amount.

#### 2.2.2 Counter Statistics representing a total amount

Their `state_class` property must be set to `total` or `total_increasing` and they may use the `last_reset` attribute. In this case Home Assistant tracks the **state**, **sum** and **last_reset** values during the statistics period and update them every 5 minutes. Computation of the **sum** field is complex and not presented here please refer to [Entities representing a total amount](https://developers.home-assistant.io/docs/core/entity/sensor/#entities-representing-a-total-amount) for more details.

The state of "*counter statistic*" represent a total amount. Entities tracking a total amount have a value that may optionally reset periodically, like this month's energy consumption, today's energy production, the weight of pellets used to heat the house over the last week or the yearly growth of a stock portfolio. The sensor's value when the first statistics is compiled is used as the initial zero-point.

This category of statistics can be further split in

1. `state_class` set to `total`
   The state represents a total amount that can both **increase and decrease**, e.g. a net energy meter. This state class should not be used for sensors where the absolute value is interesting instead of the accumulated growth or decline, for example remaining battery capacity or CPU load; in such cases the `state_class` should be set to `measurement` instead. Usage of last_reset indicates the time when an accumulating sensor such as an electricity usage meter, gas meter, water meter etc. is initialized. When changing `last_reset`, the `state` must be a valid number.
2. `state_class` set to `total_increasing`
   Similar to  statistics with `state_class` set to `total` with the restriction that the state represents a monotonically increasing positive total which periodically restarts counting from 0, e.g. a daily amount of consumed gas, weekly water consumption or lifetime energy consumption. A decreasing value is interpreted as the start of a new meter cycle or the replacement of the meter.

**Examples of counter statistics:**

- The sensor's value never resets, e.g. a lifetime total energy consumption or production: `state_class=total` with`last_reset` not set or set to `None`
- The sensor's value may reset to 0, and its value can only increase: `state_class=total_increasing`. Examples: energy consumption aligned with a billing cycle, e.g. monthly, an energy meter resetting to 0 every time it's disconnected
- The sensor's value may reset to 0, and its value can both increase and decrease: `state_class=total` with `last_reset` updated when the value resets. Examples: net energy consumption aligned with a billing cycle, e.g. monthly.
- The sensor's state is reset with every state update, for example a sensor updating every minute with the energy consumption during the past minute: `state_class=total`  with `last_reset` updated every state change.

[TODO check if information correct - Add here or in section 1.3 example of different state table for meter type and subtype]

> For detail information read [sensor developer documentation](https://developers.home-assistant.io/docs/core/entity/sensor#long-term-statistics) and [Long- and short-term statistics](https://data.home-assistant.io/docs/statistics)

### 2.3 Statistics Generation Process

Home Assistant provides support to process statistics.

1. **Entity state changes** are recorded in the `states` table to keeps track of supported entities and different elements of the entity state.

2. **Every 5 minutes**:

   - it processes the statistics entities in the state table and perform appropriate calculation.

   - statistics information are written to `statistics_short_term` table according to their category :
     - For `measurement`: **state**, **mean**, **min**, **max** are saved
     - For `counter`: **state** and **sum** (growth) and **last_reset** are saved

3. **Every 60 minutes**, short-term stats are aggregated into hourly long-term statistics

## Part 3: The Statistics Tables

In this document, we will focus solely on the `statistics_meta` and `statistics` tables. Note that the `statistics_short_term` table contains the same fields as the `statistics` table. The only difference is that this table is updated every 5 minutes and purged every 10 days.

### 3.1 statistics_meta Table

| **Field**               | **Description**                                        | **Example**                                                |
| ----------------------- | ------------------------------------------------------ | ---------------------------------------------------------- |
| **id**                  | Primary key, unique ID for each statistic              | 1, 2, 3...                                                 |
| **statistic_id**        | Entity or statistic identifier                         | "sensor.linky_urms1", "sensor.energy_daily"                |
| **source**              | Where the statistic comes from                         | "recorder" (from states), "sensor" (from sensor  platform) |
| **unit_of_measurement** | Unit of the data                                       | "V", "kWh", "W", "°C",  "%"                                |
| **has_mean**            | Deprecated  (replaced by mean_type)                    | Null                                                       |
| **has_sum**             | Boolean: Does this statistic calculate cumulative sum? | 0 or 1                                                     |
| **name**                | Human-friendly name (optional)                         | "Living Room Temperature"                                  |
| **mean_type**           | Int: What kind of mean                                 | Type of mean: 0=none, 1=arithmetic, 2=circular             |

**Understanding mean_type**

| **mean_type** | **Value** | **Meaning**              | **Use Case**                     |
| ------------- | --------- | ------------------------ | -------------------------------- |
| NONE          | 0         | No mean calculated       | Counters, totals (energy meters) |
| ARITHMETIC    | 1         | Standard arithmetic mean | Temperature, humidity, power     |
| CIRCULAR      | 2         | Circular/angular mean    | Wind direction, compass bearings |

**Mean_type / Has_sum combination table**

| **mean_type** | **has_sum** | **Type**               | **Columns Available** | **Example**          |
| ------------- | ----------- | ---------------------- | --------------------- | -------------------- |
| 1             | 0           | Arithmetic measurement | mean, min, max, state | Temperature, voltage |
| 2             | 0           | Circular measurement   | mean, min, max, state | Wind direction       |
| 0             | 1           | Total/Counter          | sum, state            | Energy meter (Linky) |

The other combinations are invalid.

### 3.2 statistics Table

**Used Fields**

| **Field**         | **Description**                                              | **Example**                                                  |
| ----------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| **id**            | Primary key for this  statistic record                       | Auto-increment                                               |
| **created_ts**    | When the statistics **were calculated and written** to the database | 2024-01-11 12:05:00                                          |
| **metadata_id**   | Foreign key to  statistics_meta                              | References  statistics_meta.id                               |
| **start_ts**      | Unix timestamp of period  start                              | 2024-01-11 12:00:00 (start of  hour)                         |
| **mean**          | Average value during the  period                             | 234.5 (average voltage)                                      |
| **mean_weight**   | is a **weight factor** used when calculating **circular mean values** for angular measurements like wind direction, where standard arithmetic averaging would be incorrect. | see [statistics fields documentation](statistics_fields_documentation.md) |
| **min**           | Minimum value during the  period                             | 230.0 (lowest voltage)                                       |
| **max**           | Maximum value during the  period                             | 238.0 (highest voltage)                                      |
| **last_reset_ts** | When the counter last  reset (for sum)                       | Timestamp of reset, or  NULL                                 |
| **state**         | Last known state at end  of period                           | 235.0 (final voltage  reading)                               |
| **sum**           | Cumulative sum (for  counters like energy)                   | 1523.4 (total kWh)                                           |

**Deprecated Fields (Still Present for Migration)**

| Field        | Replacement     | Notes                         |
| ------------ | --------------- | ----------------------------- |
| `created`    | `created_ts`    | Converted to timestamp format |
| `start`      | `start_ts`      | Converted to timestamp format |
| `last_reset` | `last_reset_ts` | Converted to timestamp format |

**Specific Fields information**

see [statistics fields documentation](statistics_fields_documentation.md) for a detail description the fields that are usually not well documented.

- The `created_ts` field is a **Unix timestamp** (float) that records **when the statistic record was created/written to the database** by Home Assistant.
- The `mean_weight` field is a **weight factor** used when calculating **circular mean values** for angular measurements like wind direction, where standard arithmetic averaging would be incorrect.

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
