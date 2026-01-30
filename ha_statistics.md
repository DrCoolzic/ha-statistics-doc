# Understanding and Using Home Assistant Statistics

## Overview

This document explains how statistics are generated in Home Assistant (HA) and how to work with them effectively. Statistics provide aggregated, long-term data storage that is more efficient than raw state history, making them essential for tracking trends, creating dashboards, and analyzing system behavior over time.

Before diving into statistics themselves, we'll explore how HA Core and the Recorder integration work, as these form the foundation for statistics generation.

---

## Part 1: Foundational Concepts

### 1.1 Simplified Home Assistant Core Behavior

Home Assistant Core is an **event-driven application** that maintains real-time state for all entities in your system. Understanding this architecture is crucial to understanding how statistics are derived.

#### Key Concepts

#### Entities and States

Entities are the basic building blocks to hold data in Home Assistant. An entity represents a sensor, actor, or function in Home Assistant. Entities are used to monitor physical properties or to control other entities. An entity is usually part of a device or a service. Entities constantly keep track of their state and associated attributes. For example:

- Entity: `light.kitchen`
- State: `on`
- Attributes: color, brightness, etc.

#### Events

Everything that happens in HA is represented as an event:

- A light being turned on
- A motion sensor being triggered
- An automation executing
- A state change occurring

Note that all entities produce state change events. Every time a state changes, a state change event is produced. State change events are just one type of event on the event bus, but there are other kinds of events, such as the [built-in events](https://www.home-assistant.io/docs/configuration/events/#built-in-events-core) that are used to coordinate between various integrations.

#### State Update Frequency

The frequency of state updates varies by integration:

- **Polling integrations**: Update at regular intervals (e.g., every 30 seconds for a temperature sensor)
- **Push-based integrations**: Update when the device reports a change (e.g., a ZigBee temperature sensor waking from sleep)
- **Event-based integrations**: Update immediately when triggered (e.g., a button press)

#### Stateless Operation

HA Core can run without persistent history. In this mode, you always know the current state of your system, but not how you arrived there. The Recorder integration provides this historical context.

> **Further Reading**: For more details, see the [Core Architecture](https://developers.home-assistant.io/docs/architecture_index) and [Entity Integration](https://developers.home-assistant.io/docs/core/entity) documentation.

---

### 1.2 The Recorder Integration

The Recorder integration stores historical data about your system in a database, enabling you to track how states change over time.

#### How Recording Works

#### Sampling and Storage

- Objects are **sampled every 5 seconds** by default (configurable)
- Values are **committed to the database only if they have changed**
- This 5-second interval is a balance between responsiveness and storage efficiency

#### Why 5 Seconds?

According to the Nyquist-Shannon sampling theorem, a 5-second sampling rate means no events are lost if they occur at intervals of **10 seconds or longer**. This covers the vast majority of entity updates while preventing database saturation during event bursts.

#### Database Backend

- **Default**: SQLite (suitable for most installations)
- **Alternatives**: PostgreSQL, MySQL/MariaDB (for advanced setups with high write volumes)

> **Further Reading**: See the [Database Schema documentation](https://www.home-assistant.io/docs/backend/database/#schema) for complete table descriptions.

---

### 1.3 The States Table

The Recorder Integration writes to numerous tables in the database, but in the context of this document, the table we are interested in is the `states` table that is the primary storage location for entity state history. Understanding its structure is essential for working with raw data and statistics.

#### Table Schema

#### Used Fields

| Field                   | Type         | Description                                                                             |
| ----------------------- | ------------ | --------------------------------------------------------------------------------------- |
| `state_id`              | INTEGER      | Primary key, auto-incrementing unique identifier for each state record                  |
| `metadata_id`           | INTEGER      | Foreign key to `states_meta` table (contains `entity_id` mapping)                       |
| `state`                 | VARCHAR(255) | The actual state value (e.g., "234.0", "on", "off", "23.5°C")                           |
| `last_updated_ts`       | FLOAT        | Unix timestamp when state was last updated (even if only attributes changed)            |
| `last_changed_ts`       | FLOAT        | Unix timestamp when the actual state value changed (NULL if same as `last_updated_ts`)  |
| `last_reported_ts`      | FLOAT        | Unix timestamp when the state was last reported by the integration                      |
| `old_state_id`          | INTEGER      | Links to the previous `state_id` for this entity (enables state history traversal)      |
| `attributes_id`         | INTEGER      | Foreign key to `state_attributes` table (stored separately to avoid duplication)        |
| `context_id_bin`        | BLOB(16)     | Binary UUID identifying the context that caused this state change                       |
| `context_user_id_bin`   | BLOB(16)     | Binary UUID of the user who initiated the change (if applicable)                        |
| `context_parent_id_bin` | BLOB(16)     | Binary UUID of the parent context (for automation chains)                               |
| `origin_idx`            | SMALLINT     | Index indicating the origin of the state change                                         |

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
- **`last_changed_ts`**: Changes only when the state value itself changes. The `last_changed_ts` field is stored as NULL when it equals `last_updated_ts` to save database space
- **`last_reported_ts`**: The timestamp from the integration/device

#### State Tracking for Statistics

The `states` table tracks all entity state changes, but in this document we focus specifically on **statistical entities** - those that generate long-term statistics. These entities belong to two main categories: the **measurement** category and the **total** category (we'll explore these in detail in Part 2).

Let's examine how state tracking works with practical examples.

##### Example 1: Tracking Instantaneous Power Consumption

Consider an integration that polls the instantaneous power consumption of a house every minute (a "measurement" type sensor). We can query the state history using:

```sql
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
    strftime('%s', '2026-01-27 13:00:00') 
    AND strftime('%s', '2026-01-27 14:00:00')
ORDER BY s.last_updated_ts;
```

| entity_id           | state | last_updated    | last_changed    | last_reported   |
| ------------------- | ----- | --------------- | --------------- | --------------- |
| sensor.linky_sinsts | 2040  | 1/27/2026 13:00 | 1/27/2026 13:00 | 1/27/2026 13:00 |
| sensor.linky_sinsts | 2030  | 1/27/2026 13:01 | 1/27/2026 13:01 | 1/27/2026 13:01 |
| sensor.linky_sinsts | 2023  | 1/27/2026 13:02 | 1/27/2026 13:02 | 1/27/2026 13:02 |
| ...                 | ...   | ...             | ...             | ...             |
| sensor.linky_sinsts | 1831  | 1/27/2026 13:57 | 1/27/2026 13:57 | 1/27/2026 13:57 |
| sensor.linky_sinsts | 1825  | 1/27/2026 13:58 | 1/27/2026 13:58 | 1/27/2026 13:58 |
| sensor.linky_sinsts | 1827  | 1/27/2026 13:59 | 1/27/2026 13:59 | 1/27/2026 13:59 |

Here we can see that we have a new state entry every minute.

##### Example 2: ZigBee Temperature Sensor

In contrast, a ZigBee temperature sensor reports values at intervals determined by the device itself, which may be irregular:

| entity_id                 | state | last_updated  | last_changed  | last_reported |
| ------------------------- | ----- | ------------- | ------------- | ------------- |
| sensor.family_temperature | 13.59 | 1/27/26 12:00 | 1/27/26 12:00 | 1/27/26 12:00 |
| sensor.family_temperature | 13.63 | 1/27/26 12:01 | 1/27/26 12:01 | 1/27/26 12:01 |
| sensor.family_temperature | 13.6  | 1/27/26 12:38 | 1/27/26 12:38 | 1/27/26 12:38 |
| sensor.family_temperature | 13.64 | 1/27/26 12:51 | 1/27/26 12:51 | 1/27/26 12:51 |

##### Example 3: Energy Meter (Total/Counter Type)

The two entities presented above belong to the **measurement** category, where state values fluctuate up and down based on current conditions. We also have entities that belong to the **total** category (e.g., energy consumption) where the state values are monotonically increasing:

| entity_id         | state    | last_updated    | last_changed    | last_reported   |
| ----------------- | -------- | --------------- | --------------- | --------------- |
| sensor.linky_east | 72199456 | 1/27/2026 12:59 | 1/27/2026 12:59 | 1/27/2026 12:59 |
| sensor.linky_east | 72199488 | 1/27/2026 13:00 | 1/27/2026 13:00 | 1/27/2026 13:00 |
| sensor.linky_east | 72199520 | 1/27/2026 13:01 | 1/27/2026 13:01 | 1/27/2026 13:01 |
| ...               | ...      | ...             | ...             | ...             |
| sensor.linky_east | 72201168 | 1/27/2026 13:58 | 1/27/2026 13:58 | 1/27/2026 13:58 |
| sensor.linky_east | 72201200 | 1/27/2026 13:59 | 1/27/2026 13:59 | 1/27/2026 13:59 |
| sensor.linky_east | 72201224 | 1/27/2026 14:00 | 1/27/2026 14:00 | 1/27/2026 14:00 |

---

## Part 2: Statistics Generation

### 2.1 What Are Statistics?

Home Assistant supports statistics, which are **aggregated and compressed representations** of entity data over time. Unlike the `states` table, which stores every state change, the statistics system stores information at regular intervals:

- **Short-term statistics**: Every 5 minutes (stored in `statistics_short_term` table)
- **Long-term statistics**: Every hour (stored in `statistics` table)

This dramatically reduces storage requirements while preserving trend data.

#### Short-term vs Long-term Statistics

| Aspect | Short-term Statistics | Long-term Statistics |
|--------|---------------- ------|---------------- -----|
| **Interval** | 5 minutes | 1 hour |
| **Retention** | 10 days (auto-purged) | Indefinite (or per purge settings) |
| **Table** | `statistics_short_term` | `statistics` |
| **Purpose** | Recent detailed trends | Historical trend analysis |
| **Generation** | Direct from states table | Aggregated from short-term stats |

### 2.2 Which Entities Generate Statistics?

Statistics are automatically generated for **entities** that meet certain criteria. While most statistical entities are in the `sensor` domain, ANY entity with an appropriate `state_class` can generate statistics, regardless of domain.

Statistical entities can be classified into two categories: **measurement statistics** and **counter statistics**.

#### 2.2.1 Measurement Statistics (Representing a Measurement)

**Requirements:**

- `state_class` property must be set to `measurement` or `measurement_angle`
- The `device_class` must not be either of `date`, `enum`, `energy`, `gas`, `monetary`, `timestamp`, `volume` or `water`
- Must have a `unit_of_measurement` defined

**What is tracked:**
Home Assistant tracks the **min**, **max**, and **mean** values during each statistics period, updating them every 5 minutes.

**Important:** The `state` of "measurement statistics" represents a **real-time measurement at a point in time**, such as current temperature, humidity, or electrical power. Their state should represent a **current measurement**, not historical data, aggregations, or forecasts. For example:

- ✅ Current temperature: 22.5°C
- ✅ Current power consumption: 1500W
- ❌ Tomorrow's forecast temperature
- ❌ Yesterday's energy consumption
- ❌ Average temperature over the last hour

**Special case - Angular Measurements (`measurement_angle`):**
For sensors with `state_class: measurement_angle`, the state represents a real-time measurement for angles measured in degrees (°), such as current wind direction. These use **circular mean** calculations (mean_type=2) to correctly average angles. For example, averaging 350° and 10° correctly yields 0° (North), not 180° (South).

Note that measurement statistics do not represent a total amount.

#### 2.2.2 Counter Statistics (Representing a Total Amount)

**Requirements:**

- `state_class` property must be set to `total` or `total_increasing`
- May use the `last_reset` attribute
- Must have a `unit_of_measurement` defined

**What is tracked:**
Home Assistant tracks the **state**, **sum**, and **last_reset** values during each statistics period, updating them every 5 minutes.

**The sum field:**
The **sum** field tracks the cumulative growth/change over time:

- For counters that reset: sum tracks total consumption across resets
- For monotonically increasing counters: sum = current_value - initial_value
- State changes are converted to growth/consumption amounts

For detailed algorithms, see [Entities representing a total amount](https://developers.home-assistant.io/docs/core/entity/sensor/#entities-representing-a-total-amount).

**What the state represents:**
The state of "counter statistics" represents a total amount. Entities tracking a total amount have a value that may optionally reset periodically, such as:

- This month's energy consumption
- Today's energy production
- The weight of pellets used to heat the house over the last week
- The yearly growth of a stock portfolio

The sensor's value when the first statistics is compiled is used as the initial zero-point.

#### Counter Statistics Subtypes

This category of statistics can be further split into:

##### 1. `state_class: total`

The state represents a total amount that can both **increase and decrease**, e.g., a net energy meter.

**Important:** This state class should not be used for sensors where the absolute value is interesting instead of the accumulated growth or decline. For example, remaining battery capacity or CPU load should use `state_class: measurement` instead.

**About last_reset:**
`last_reset` indicates when the counter was reset to zero (e.g., start of a new billing period). When `last_reset` changes, the `state` must be a valid number.

##### 2. `state_class: total_increasing`

Similar to statistics with `state_class: total` with the restriction that the state represents a **monotonically increasing positive total** which periodically restarts counting from 0, e.g., a daily amount of consumed gas, weekly water consumption, or lifetime energy consumption. A decreasing value is interpreted as the start of a new meter cycle or the replacement of the meter.

#### Examples of Counter Statistics Configuration

- **Lifetime total (never resets)**: `state_class=total` with `last_reset` not set or set to `None`
  - Example: Lifetime total energy consumption or production
  
- **Resetting counter (only increases)**: `state_class=total_increasing`
  - Examples: Monthly energy consumption, energy meter that resets when disconnected
  
- **Resetting counter (can increase/decrease)**: `state_class=total` with `last_reset` updated when value resets
  - Example: Monthly net energy consumption (with solar panels)
  
- **Differential sensor**: `state_class=total` with `last_reset` updated every state change
  - Example: Sensor updating every minute with energy consumption during the past minute

> For detailed information, read the [sensor developer documentation](https://developers.home-assistant.io/docs/core/entity/sensor#long-term-statistics) and [Long- and short-term statistics](https://data.home-assistant.io/docs/statistics)

### 2.3 Statistics Generation Process

Home Assistant provides support to process statistics through the following workflow:

1. **Entity state changes** are recorded in the `states` table, which keeps track of supported entities and different elements of the entity state.

2. **Every 5 minutes**, the statistics compilation process:
   - Processes the statistical entities in the states table and performs appropriate calculations
   - Writes statistics information to the `statistics_short_term` table according to their category:
     - For `measurement`: **state**, **mean**, **min**, **max** are saved
     - For `total`/`total_increasing`: **state**, **sum** (growth), and **last_reset** are saved

3. **Every 60 minutes**, short-term statistics are aggregated into hourly long-term statistics in the `statistics` table.

#### Important Notes on Statistics Generation

- **No retroactive generation**: Statistics are only generated going forward from when `state_class` is first set
- **Historical states are not converted**: States recorded before `state_class` was added will not be converted to statistics
- **Missing data handling**: Gaps in state data create gaps in statistics. `unavailable` and `unknown` states are not included in calculations
- **Unit changes**: Changing `unit_of_measurement` breaks statistics continuity and creates a new statistic_id

### 2. 4 Statistics Computation Process

It worth noting that the `statistics/statistics_short_term` tables are not entirely built from `states`. In practice, the statistics compiler pulls data from multiple recorder sources depending on what exists for the entity and the period being compiled:

- **`states` / `states_meta`**: state changes (the classic recorder rows).
- **`state_attributes`** (in older schemas) or JSON attributes stored with the state row (depending on your DB/version): needed because statistics often rely on the entity’s `state_class`, `device_class`, `unit_of_measurement`, etc.
- **`statistics` itself**: Home Assistant can *continue* long-term statistics by using the **previous statistics row** as the starting point (especially important for “total increasing”/counter-like entities). So a new hour/day’s stats can depend on the prior period’s compiled stats, not only raw `states`.
- **(Sometimes) `events`**: not for normal sensor statistics, but worth knowing that recorder has other data sources; some integrations rely on event history rather than state history for certain kinds of analytics.

> Statistics are computed from *recorded history*, which includes `states`, but may also require metadata/attributes and may chain from previously compiled statistics for continuity.

#### 2.4.1 Computation for Measurement Statistics

For entities with `state_class: measurement` or `measurement_angle`, Home Assistant calculates **min**, **max**, and **mean** values during each statistics period.

#### For `state_class: measurement` (Arithmetic Mean)

**Data Collection:**

- Every 5 seconds (by default), the Recorder samples the current entity state
- Only valid numeric states are considered (`unavailable` and `unknown` are excluded)
- Non-numeric values and unit changes are skipped

**Calculation Process (per 5-minute or 1-hour period):**

1. **Mean (Arithmetic Average)**:
   - Sum all valid numeric state values in the period
   - Divide by the number of valid samples
   - Formula: `mean = Σ(state_values) / n`
   - Example: States [2040, 2030, 2023] → mean = (2040+2030+2023)/3 = 2031
2. **Min (Minimum)**:
   - The lowest valid numeric value observed during the period
   - Example: States [2040, 2030, 2023] → min = 2023
3. **Max (Maximum)**:
   - The highest valid numeric value observed during the period
   - Example: States [2040, 2030, 2023] → max = 2040
4. **State**:
   - The last valid numeric state value at the end of the period
   - If the final state is `unavailable`, uses the last known good value
   - Example: If last state at 13:04:58 is 2023 → state = 2023

**Storage:** In `statistics_meta`: `mean_type=1` (arithmetic), `has_sum=0`

In `statistics`/`statistics_short_term`: `mean`, `min`, `max`, `state` are populated; `sum` and `last_reset_ts` are NULL

#### For `state_class: measurement_angle` (Circular Mean)

Angular measurements (like wind direction in degrees) require special handling because standard arithmetic averaging fails for angles. For example, the average of 350° and 10° should be 0° (North), not 180° (South).

**Circular Mean Calculation:**

1. Convert each angle θ to unit vectors:
   - x = cos(θ)
   - y = sin(θ)
2. Calculate average vector components:
   - mean_x = Σ(cos(θᵢ)) / n
   - mean_y = Σ(sin(θᵢ)) / n
3. Convert back to angle:
   - mean = atan2(mean_y, mean_x)
   - Convert from radians to degrees if needed
4. **Mean Weight**:
   - Stored as the length of the average vector: `sqrt(mean_x² + mean_y²)`
   - Values close to 1 indicate consistent direction
   - Values close to 0 indicate scattered directions

**Min and Max:**

- For angular measurements, min/max are still the literal minimum and maximum degree values observed
- Note: These may be less meaningful for circular data

**Storage:** In `statistics_meta`: `mean_type=2` (circular), `has_sum=0`

In `statistics`/`statistics_short_term`: `mean`, `min`, `max`, `state`, and `mean_weight` are populated; `sum` and `last_reset_ts` are NULL

### 2.4.2 Computation for Counter Statistics

For entities with `state_class: total` or `total_increasing`, Home Assistant tracks cumulative values using **state**, **sum**, and **last_reset**.

#### Understanding the Fields

**`state`**: The absolute meter/counter reading at the end of the period

- For energy meters: the total lifetime kWh reading
- Example: 72201200.0 kWh (absolute meter value)

**`sum`**: The cumulative growth/consumption since statistics began

- Represents total consumption from the statistics "zero point"
- When statistics first start, the initial state becomes the baseline
- sum = current_state - initial_state (when statistics began)
- Example: If initial state was 71905320 and current state is 72201200, then sum = 295880 kWh

**`last_reset_ts`**: Timestamp when the counter was last reset (if applicable)

- Read from the entity's `last_reset` attribute
- NULL for lifetime counters that never reset
- Updated when the `last_reset` attribute changes

#### For `state_class: total_increasing` (Monotonically Increasing)

**Characteristics:**

- Counter only increases (or resets to zero/low value)
- Examples: Energy consumption, water usage, production counters
- Decreases are interpreted as meter resets or replacements

**Calculation Process:**

1. **State**: Last valid numeric value at end of period
2. **Sum Calculation**:
   - First statistics record: `sum = state - initial_state` (usually 0 or small value)
   - Subsequent records: `sum = previous_sum + (current_state - previous_state)`
   - If `current_state < (previous_state * 0.9)` (reset detected): treat as counter reset
     - Continue sum calculation: `sum = previous_sum + current_state` (assuming reset to 0)
   - Sum continuously accumulates, even across meter resets
3. **Last Reset**: Usually NULL unless entity provides `last_reset` attribute

Note that Home Assistant uses a **10% threshold** to detect resets rather than treating any small decrease as a reset to prevent false reset detection.

**Example from Energy Meter presented in Part 1 (sensor.linky_east):**

```text
13:00: state=72199616, sum=294296 (previous_sum + delta since 12:55)
13:05: state=72199768, sum=294448 (294296 + (72199768-72199616) = 294296 + 152)
13:10: state=72199920, sum=294600 (294448 + (72199920-72199768) = 294448 + 152)
...
14:00: state=72201200, sum=295880 (accumulated growth)
```

#### For `state_class: total` (Can Increase or Decrease)

**Characteristics:**

- Counter can increase OR decrease
- Examples: Net energy meter (with solar), battery charge level as counter
- Uses `last_reset` attribute to track counter resets

**Calculation Process:**

1. **State**: Last valid numeric value at end of period
2. **Sum Calculation**:
   - If `last_reset` hasn't changed: `sum = previous_sum + (current_state - previous_state)`
   - If `last_reset` changed: reset detected, restart accumulation
     - New sum starts from current state value
   - Can go up or down based on state changes
3. **Last Reset**:
   - Copied from entity's `last_reset` attribute
   - When this changes, sum calculation restarts

#### Special Case: Differential Sensors

For sensors that update frequently with differential values (e.g., "energy consumed in the last minute"), configure with `state_class: total` and update `last_reset` with every state change. This tells HA to treat each state value as a new differential rather than a continuous counter.

**Storage:** In `statistics_meta`: `mean_type=0` (none), `has_sum=1`

In `statistics`/`statistics_short_term`: `state`, `sum`, and `last_reset_ts` are populated; `mean`, `min`, `max` are NULL

### 2.4.3 Computing Delta/Growth from Statistics

While the statistics tables store cumulative `sum` values, dashboards and graphs often need to display **consumption or growth during a specific period**. This delta is computed from the `sum` field.

#### Formula

##### Delta (consumption/growth) = sum_end - sum_start

Where:

- `sum_start` = sum value at the beginning of the desired period
- `sum_end` = sum value at the end of the desired period

#### Example: Hourly Energy Consumption

Using the sensor.linky_east data from Example 3:

```sql
-- Get hourly consumption
SELECT 
  sm.statistic_id,
  datetime(s.start_ts, 'unixepoch', 'localtime') as period_start,
  s.sum as cumulative_sum,
  s.sum - LAG(s.sum) OVER (ORDER BY s.start_ts) as period_consumption
FROM statistics s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.linky_east'
  AND datetime(s.start_ts, 'unixepoch', 'localtime') >= '2026-01-27 12:00:00'
  AND datetime(s.start_ts, 'unixepoch', 'localtime') < '2026-01-27 15:00:00'
ORDER BY s.start_ts;
```

Result:

| statistic_id      | period_start    | cumulative_sum | period_consumption |
| ----------------- | --------------- | -------------- | ------------------ |
| sensor.linky_east | 1/27/2026 12:00 | 294136         |                    |
| sensor.linky_east | 1/27/2026 13:00 | 295880         | 1744               |
| sensor.linky_east | 1/27/2026 14:00 | 297544         | 1664               |

**Interpretation:**

- Between 12:00-13:00: consumed 1744 Wh (1.74 kWh)
- Between 13:00-14:00: consumed 1664 Wh (1.6 kWh)

#### Using last_reset for Multi-Day Calculations

When calculating deltas across longer periods, check `last_reset_ts`:

- **If last_reset unchanged**: Simple subtraction `sum_end - sum_start`
- **If last_reset changed**: The counter was reset during the period
  - For `total_increasing`: sum continues accumulating across resets (simple subtraction still works)
  - For `total` with manual resets: May need special handling depending on use case

#### How Statistics Graph Card Uses This

The built-in statistics graph card:

1. Queries the relevant statistics rows for the time range
2. Calculates deltas: `consumption_in_period[i] = sum[i] - sum[i-1]`
3. Displays as bar chart (for consumption) or line chart (for cumulative)

This is why the `sum` field exists: to enable efficient delta calculations without reprocessing all raw states.

### 2.5 The Statistics Tables

In this document, we will focus on the `statistics_meta` and `statistics` tables. Note that the `statistics_short_term` table contains the same fields as the `statistics` table. The only difference is that the short-term table is updated every 5 minutes and automatically purged after 10 days.

#### 2.5.1 statistics_meta Table

| Field                   | Description                                                  | Example                                                   |
| ----------------------- | ------------------------------------------------------------ | --------------------------------------------------------- |
| `id`                    | Primary key, unique ID for each statistic                    | 1, 2, 3...                                                |
| `statistic_id`          | Entity or statistic identifier                               | "sensor.linky_urms1", "sensor.energy_daily"               |
| `source`                | Where the statistic comes from                               | "recorder" (from states), "sensor" (from sensor platform) |
| `unit_of_measurement`   | Unit of the data                                             | "V", "kWh", "W", "°C", "%"                                |
| `has_mean`              | Deprecated (replaced by mean_type)                           | NULL                                                      |
| `has_sum`               | Boolean: Does this statistic calculate cumulative sum?       | 0 or 1                                                    |
| `name`                  | Human-friendly name (optional)                               | "Living Room Temperature"                                 |
| `mean_type`             | Integer: What kind of mean calculation is used               | 0=none, 1=arithmetic, 2=circular                          |

#### Understanding mean_type

| mean_type | Value | Meaning                  | Use Case                         |
| --------- | ----- | ------------------------ | -------------------------------- |
| None      | 0     | No mean calculated       | Counters, totals (energy meters) |
| Arithmetic| 1     | Standard arithmetic mean | Temperature, humidity, power     |
| Circular  | 2     | Circular/angular mean    | Wind direction, compass bearings |

#### Mean_type / Has_sum Combination Table

| mean_type | has_sum | Type                   | Columns Available     | Example              |
| --------- | ------- | ---------------------- | --------------------- | -------------------- |
| 1         | 0       | Arithmetic measurement | mean, min, max, state | Temperature, voltage |
| 2         | 0       | Circular measurement   | mean, min, max, state | Wind direction       |
| 0         | 1       | Total/Counter          | sum, state            | Energy meter (Linky) |

The other combinations are invalid.

#### 2.5.2 statistics Table

#### Statistics Used Fields

| Field           | Description                                                     | Example                                                  |
| --------------- | --------------------------------------------------------------- | -------------------------------------------------------- |
| `id`            | Primary key for this statistic record                           | Auto-increment                                           |
| `created_ts`    | When the statistics were calculated and written to the database | 2024-01-11 12:05:00                                      |
| `metadata_id`   | Foreign key to statistics_meta                                  | References statistics_meta.id                            |
| `start_ts`      | Unix timestamp of period start                                  | 2024-01-11 12:00:00 (start of hour)                      |
| `mean`          | Average value during the period                                 | 234.5 (average voltage)                                  |
| `mean_weight`   | Weight factor for circular averaging (angular measurements)     | See [statistics fields documentation](stat_fields.md)    |
| `min`           | Minimum value during the period                                 | 230.0 (lowest voltage)                                   |
| `max`           | Maximum value during the period                                 | 238.0 (highest voltage)                                  |
| `last_reset_ts` | When the counter last reset (for sum)                           | Timestamp of reset, or NULL                              |
| `state`         | Last known state at end of period                               | 235.0 (final voltage reading)                            |
| `sum`           | Cumulative sum (for counters like energy)                       | 1523.4 (total kWh)                                       |

#### Deprecated statistics fields (Still Present for Migration)

| Field        | Replacement     | Notes                         |
| ------------ | --------------- | ----------------------------- |
| `created`    | `created_ts`    | Converted to timestamp format |
| `start`      | `start_ts`      | Converted to timestamp format |
| `last_reset` | `last_reset_ts` | Converted to timestamp format |

#### Specific Fields Information

See [statistics fields documentation](statistics_fields_documentation.md) for a detailed description of fields that are not well documented elsewhere:

**`created_ts`**: A Unix timestamp (float) that records when the statistic record was created/written to the database by Home Assistant (typically at or shortly after `start_ts + period_duration`)

**`mean_weight`**: A weight factor used when calculating circular mean values for angular measurements like wind direction, where standard arithmetic averaging would be incorrect

### 2.6 Short and long term Statistics tracking

We now look at what is stored in the statistics_short_term table and statistics table using the same practical examples used in Part 1

#### Example 1: Power Consumption

We use the following query to retrieve information from the statistics  tables

```sqlite
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
```

##### Short term statistics

| statistic_id        | period_start    | created_at      | mean        | min  | max  |
| ------------------- | --------------- | --------------- | ----------- | ---- | ---- |
| sensor.linky_sinsts | 1/27/2026 13:00 | 1/27/2026 13:05 | 2026.510631 | 1987 | 2040 |
| sensor.linky_sinsts | 1/27/2026 13:05 | 1/27/2026 13:10 | 1973.135533 | 1958 | 1989 |
| sensor.linky_sinsts | 1/27/2026 13:10 | 1/27/2026 13:15 | 1955.405006 | 1952 | 1959 |
| sensor.linky_sinsts | 1/27/2026 13:15 | 1/27/2026 13:20 | 1889.207249 | 1840 | 1966 |
| sensor.linky_sinsts | 1/27/2026 13:20 | 1/27/2026 13:25 | 1822.634674 | 1789 | 1857 |
| sensor.linky_sinsts | 1/27/2026 13:25 | 1/27/2026 13:30 | 1857.703889 | 1834 | 1880 |
| sensor.linky_sinsts | 1/27/2026 13:30 | 1/27/2026 13:35 | 1826.921793 | 1786 | 1857 |
| sensor.linky_sinsts | 1/27/2026 13:35 | 1/27/2026 13:40 | 1754.036337 | 1704 | 1863 |
| sensor.linky_sinsts | 1/27/2026 13:40 | 1/27/2026 13:45 | 1849.280724 | 1825 | 1863 |
| sensor.linky_sinsts | 1/27/2026 13:45 | 1/27/2026 13:50 | 1890.200181 | 1783 | 1912 |
| sensor.linky_sinsts | 1/27/2026 13:50 | 1/27/2026 13:55 | 1797.37581  | 1780 | 1846 |
| sensor.linky_sinsts | 1/27/2026 13:55 | 1/27/2026 14:00 | 1826.968478 | 1822 | 1831 |

##### Long Term Statistics

| statistic_id        | period_start    | created_at      | mean        | min  | max  |
| ------------------- | --------------- | --------------- | ----------- | ---- | ---- |
| sensor.linky_sinsts | 1/27/2026 13:00 | 1/27/2026 14:00 | 1872.448359 | 1704 | 2040 |

#### Example 2: ZigBee Temperature Sensor Statistics

##### Zigbee Short Term Statistics

| statistic_id              | period_start    | created_at      | mean  | min   | max   |
| ------------------------- | --------------- | --------------- | ----- | ----- | ----- |
| sensor.family_temperature | 1/27/26 1:00 PM | 1/27/26 1:05 PM | 13.61 | 13.57 | 13.63 |
| sensor.family_temperature | 1/27/26 1:05 PM | 1/27/26 1:10 PM | 13.63 | 13.63 | 13.63 |
| sensor.family_temperature | 1/27/26 1:10 PM | 1/27/26 1:15 PM | 13.63 | 13.63 | 13.63 |
| sensor.family_temperature | 1/27/26 1:15 PM | 1/27/26 1:20 PM | 13.63 | 13.63 | 13.63 |
| sensor.family_temperature | 1/27/26 1:20 PM | 1/27/26 1:25 PM | 13.63 | 13.63 | 13.63 |
| sensor.family_temperature | 1/27/26 1:25 PM | 1/27/26 1:30 PM | 13.63 | 13.63 | 13.63 |
| sensor.family_temperature | 1/27/26 1:30 PM | 1/27/26 1:35 PM | 13.63 | 13.63 | 13.63 |
| sensor.family_temperature | 1/27/26 1:35 PM | 1/27/26 1:40 PM | 13.61 | 13.6  | 13.63 |
| sensor.family_temperature | 1/27/26 1:40 PM | 1/27/26 1:45 PM | 13.6  | 13.6  | 13.6  |
| sensor.family_temperature | 1/27/26 1:45 PM | 1/27/26 1:50 PM | 13.6  | 13.6  | 13.6  |
| sensor.family_temperature | 1/27/26 1:50 PM | 1/27/26 1:55 PM | 13.62 | 13.6  | 13.64 |
| sensor.family_temperature | 1/27/26 1:55 PM | 1/27/26 2:00 PM | 13.64 | 13.64 | 13.64 |

##### Zigbee Long Term Statistics

| statistic_id        | period_start        | created_at          | mean    | min  | max  |
| ------------------- | ------------------- | ------------------- | ------- | ---- | ---- |
| sensor.linky_sinsts | 2026-01-27 13:00:00 | 2026-01-27 14:00:10 | 2492.16 | 1955 | 5530 |

#### Example 3: Energy Meter (Total/Counter Type) Statistics

For a total type of statistics we need to look at different fields so we use the following query

```sqlite
SELECT 
  sm.statistic_id,
  datetime(s.start_ts, 'unixepoch', 'localtime') as period_start,
  datetime(s.created_ts, 'unixepoch', 'localtime') as created_at,
  s.state,
  s.sum,
  datetime(s.last_reset_ts, 'unixepoch', 'localtime') as last_reset,
  s.sum - LAG(s.sum) OVER (ORDER BY s.start_ts) as period_consumption
FROM statistics_short_term s
INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
WHERE sm.statistic_id = 'sensor.linky_east'
 AND datetime(s.start_ts, 'unixepoch', 'localtime') >= '2026-01-27 13:00:00'
 AND datetime(s.start_ts, 'unixepoch', 'localtime') < '2026-01-27 14:00:00'
ORDER BY s.start_ts ASC;
```

##### Counter Short Term Statistics

| statistic_id      | period_start    | created_at      | state    | sum    | last_reset | period_consumption |
| ----------------- | --------------- | --------------- | -------- | ------ | ---------- | ------------------ |
| sensor.linky_east | 1/27/2026 13:00 | 1/27/2026 13:05 | 72199616 | 294296 |            |                    |
| sensor.linky_east | 1/27/2026 13:05 | 1/27/2026 13:10 | 72199768 | 294448 |            | 152                |
| sensor.linky_east | 1/27/2026 13:10 | 1/27/2026 13:15 | 72199920 | 294600 |            | 152                |
| sensor.linky_east | 1/27/2026 13:15 | 1/27/2026 13:20 | 72200064 | 294744 |            | 144                |
| sensor.linky_east | 1/27/2026 13:20 | 1/27/2026 13:25 | 72200208 | 294888 |            | 144                |
| sensor.linky_east | 1/27/2026 13:25 | 1/27/2026 13:30 | 72200352 | 295032 |            | 144                |
| sensor.linky_east | 1/27/2026 13:30 | 1/27/2026 13:35 | 72200488 | 295168 |            | 136                |
| sensor.linky_east | 1/27/2026 13:35 | 1/27/2026 13:40 | 72200624 | 295304 |            | 136                |
| sensor.linky_east | 1/27/2026 13:40 | 1/27/2026 13:45 | 72200768 | 295448 |            | 144                |
| sensor.linky_east | 1/27/2026 13:45 | 1/27/2026 13:50 | 72200920 | 295600 |            | 152                |
| sensor.linky_east | 1/27/2026 13:50 | 1/27/2026 13:55 | 72201056 | 295736 |            | 136                |
| sensor.linky_east | 1/27/2026 13:55 | 1/27/2026 14:00 | 72201200 | 295880 |            | 144                |

##### Counter Long Term Statistics

| statistic_id      | period_start    | created_at      | state    | sum    | last_reset | period_consumption |
| ----------------- | --------------- | --------------- | -------- | ------ | ---------- | ------------------ |
| sensor.linky_east | 1/27/2026 12:00 | 1/27/2026 13:00 | 72199456 | 294136 |            |                    |
| sensor.linky_east | 1/27/2026 13:00 | 1/27/2026 14:00 | 72201200 | 295880 |            | 1744               |
| sensor.linky_east | 1/27/2026 14:00 | 1/27/2026 15:00 | 72202864 | 297544 |            | 1664               |

---

## Part 3: Working with Statistics

### 3.1 Benefits of Statistics

- **Reduced storage**: Hourly aggregates vs. potentially hundreds of state changes
- **Faster queries**: Pre-aggregated data loads much faster
- **Long-term retention**: Keep years of trend data without massive databases
- **Energy dashboard**: Powers the built-in energy monitoring features

### 3.2 Accessing Statistics

#### Via the UI

- [Developer Tools](https://www.home-assistant.io/docs/tools/dev-tools/) → Statistics
- Energy Dashboard (for energy entities)
- [History graphs](https://www.home-assistant.io/dashboards/history-graph/) automatically use statistics for long time ranges
- [History panels](https://www.home-assistant.io/integrations/history/)
- [Statistics graph card](https://www.home-assistant.io/dashboards/statistics-graph)
- And many many custom card

#### Via Services

- `recorder.import_statistics`: Import external statistics
- `recorder.adjust_sum`: Correct cumulative values (e.g., after meter replacement)

#### Via Database

- Direct SQL queries to `statistics` and `statistics_short_term` tables
- Useful for advanced analysis and custom integrations

### 3.3 Common Use Cases

#### Energy Monitoring

Track total energy consumption with `total_increasing` state class, automatically handling meter resets.

#### Temperature Trends

Use `measurement` state class to track min/max/average temperatures over months or years.

#### Cost Tracking

Combine consumption statistics with pricing data to calculate costs.

#### Performance Analysis

Identify patterns in system behavior over extended periods.

---

## Part 4: Best Practices and Troubleshooting

### 4.1 Configuration Recommendations

#### Purge Settings

Adjust recorder purge settings based on your storage capacity:

```yaml
recorder:
  purge_keep_days: 7  # Keep detailed states for 7 days
  commit_interval: 1  # Commit to DB every second (higher load, less data loss risk)
  # Note: Statistics have separate retention:
  # - Short-term statistics auto-purge after 10 days
  # - Long-term statistics kept indefinitely unless manually purged
```

#### Include/Exclude Entities

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

#### Missing Statistics

- Verify entity has `state_class` attribute
- Check entity provides numerical values
- Ensure recorder is including the entity
- Check Developer Tools → Statistics for errors

#### Incorrect Values

- Use `recorder.adjust_sum` service to fix cumulative totals
- Check for unit conversions in entity attributes
- Verify state changes are being recorded in `states` table

#### Performance Issues

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

## References

### [Home Assistant Documentation](https://www.home-assistant.io/docs/)

- [Events](https://www.home-assistant.io/docs/configuration/events/)
- [Entities and domains](https://www.home-assistant.io/docs/configuration/entities_domains/)
- [State and state object](https://www.home-assistant.io/docs/configuration/state_object/)
- [Database](https://www.home-assistant.io/docs/backend/database/)
- [Developer tools](https://www.home-assistant.io/docs/tools/dev-tools/#statistics-tab)
- [Recorder integration](https://www.home-assistant.io/integrations/recorder/)
- [History integration](https://www.home-assistant.io/integrations/history/)
- [Filter integration](https://www.home-assistant.io/integrations/filter/)
- [Statistics integration](https://www.home-assistant.io/integrations/statistics/)
- [Analytics Integration](https://www.home-assistant.io/integrations/analytics/)

## [Home Assistant Developer Docs](https://developers.home-assistant.io/)

- [Sensor entity](https://developers.home-assistant.io/docs/core/entity/sensor)
- [Clear up storage](https://www.home-assistant.io/more-info/free-space/)
- [Core architecture](https://developers.home-assistant.io/docs/architecture/core/)
- [Entity interaction with Home Assistant Core](https://developers.home-assistant.io/docs/architecture/devices-and-services/#entity-interaction-with-home-assistant-core)
- [Long Term Statistics](https://developers.home-assistant.io/docs/core/entity/sensor/#long-term-statistics)

## [Home Assistant Data Science Portal](https://data.home-assistant.io/)

- [Long- and short-term statistics | Home Assistant Data Science Portal](https://data.home-assistant.io/docs/statistics/)
- [Home Assistant Data Science | Home Assistant Data Science Portal](https://data.home-assistant.io/)
- [Home Assistant Recorder Runs | Home Assistant Data Science Portal](https://data.home-assistant.io/docs/recorder/)

## Other Web Pages

- [Taming my Home Assistant database growth - Koskila.net](https://www.koskila.net/taming-my-home-assistant-database-growth/)
- [Maîtriser votre base de données Home Assistant](https://www.hacf.fr/bd-recorder-statistiques/#les-données-dans-ha)
- [Custom Integration to import long term statistics from a file like csv or tsv - Share your Projects! / Custom Integrations - Home Assistant Community](https://community.home-assistant.io/t/custom-integration-to-import-long-term-statistics-from-a-file-like-csv-or-tsv/689793)
- [Migrate back from MariaDB to the default SQLite - Community Guides - Home Assistant Community](https://community.home-assistant.io/t/migrate-back-from-mariadb-to-the-default-sqlite/604278)
- [Loading, Manipulating, Recovering and Moving Long Term Statistics in Home Assistant - Community Guides - Home Assistant Community](https://community.home-assistant.io/t/loading-manipulating-recovering-and-moving-long-term-statistics-in-home-assistant/953802)
- [Migrer des données historiques entre deux instances Home Asssistant | LPRP.fr](https://www.lprp.fr/2025/06/home-assistant-migration-donnees/)
- [Mastering Home Assistant's Recorder and History: Optimizing Data for Performance and Insight](https://newerest.space/mastering-home-assistant-recorder-history-optimization/)
- [Display / output Home Assistant data as a table - Reporting](https://www.libe.net/en/ha-tabledata)
- [Updating statistics from integration and calculation of max, min, mean values - Development - Home Assistant Community](https://community.home-assistant.io/t/updating-statistics-from-integration-and-calculation-of-max-min-mean-values/824001)

## Other GitHub Page

- [Domain vs platform vs component vs integration vs ... · Issue #570 · home-assistant/developers.home-assistant](https://github.com/home-assistant/developers.home-assistant/issues/570)
- [DrEvily/Home-Assistant-Sensor-Visualizer: Tool to analyse csv exported Entities from Home Assistant Recorder. Exported Sensor data can be visulaized and analyzed with HA_Sensor_Visualizer. It allows to zoom into data as well as with cursor individual datapoints can be analyzed.](https://github.com/DrEvily/Home-Assistant-Sensor-Visualizer)
- [Core Entity Types | home-assistant/home-assistant.io | DeepWiki](https://deepwiki.com/home-assistant/home-assistant.io/7.1-core-entity-types)
- [What Are Entities In Home Assistant?](https://spicehometech.com/how-to/basics/what-are-entities-in-home-assistant/)
- [Entity | Home Assistant Developer Docs](https://developers.home-assistant.io/docs/core/entity/)
- [alexarch21/history-explorer-card: A card for Home Assistant Lovelace for exploring the history of your entities interactively and in real time.](https://github.com/alexarch21/history-explorer-card) (deprecated)
