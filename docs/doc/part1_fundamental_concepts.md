# Part 1: Foundational Concepts

## 1.1 Simplified Home Assistant Core Behavior

Home Assistant Core is an **event-driven application** that maintains real-time state for all entities in your system. Understanding this architecture is crucial to understanding how statistics are derived.

### Key Concepts

### Entities and States

Entities are the basic building blocks to hold data in Home Assistant. An entity represents a sensor, actor, or function in Home Assistant. Entities are used to monitor physical properties or to control other entities. An entity is usually part of a device or a service. Entities constantly keep track of their state and associated attributes. For example:

- Entity: `light.kitchen`
- State: `on`
- Attributes: color, brightness, etc.

### Events

Everything that happens in HA is represented as an event:

- A light being turned on
- A motion sensor being triggered
- An automation executing
- A state change occurring

Note that all entities produce state change events. Every time a state changes, a state change event is produced. State change events are just one type of event on the event bus, but there are other kinds of events, such as the [built-in events](https://www.home-assistant.io/docs/configuration/events/#built-in-events-core) that are used to coordinate between various integrations.

### State Update Frequency

The frequency of state updates varies by integration:

- **Polling integrations**: Update at regular intervals (e.g., every 30 seconds for a temperature sensor)
- **Push-based integrations**: Update when the device reports a change (e.g., a ZigBee temperature sensor waking from sleep)
- **Event-based integrations**: Update immediately when triggered (e.g., a button press)

### Stateless Operation

HA Core can run without persistent history. In this mode, you always know the current state of your system, but not how you arrived there. The Recorder integration provides this historical context.

> **Further Reading**: For more details, see the [Core Architecture](https://developers.home-assistant.io/docs/architecture_index) and [Entities: integrating devices & services](https://developers.home-assistant.io/docs/architecture/devices-and-services/) documentation.

---

## 1.2 The Recorder Integration

The Recorder integration stores historical data about your system in a database, enabling you to track how states change over time.

### How Recording Works

#### Sampling and Storage

- Objects are **sampled every 5 seconds** by default (configurable)
- Values are **committed to the database only if they are valid and if they have changed**
- This 5-second interval is a balance between responsiveness and storage efficiency. According to the Nyquist-Shannon sampling theorem, a 5-second sampling rate means no events are lost if they occur at intervals of **10 seconds or longer**. This covers the vast majority of entity updates while preventing database saturation during event bursts.

#### Database Backend

- **Default**: SQLite (suitable for most installations)
- **Alternatives**: PostgreSQL, MySQL/MariaDB (for advanced setups with high write volumes)

> **Further Reading**: See the [Database Schema documentation](https://www.home-assistant.io/docs/backend/database/#schema) for complete table descriptions.

---

## 1.3 The States Table

The Recorder Integration writes to numerous tables in the database, but in the context of this document, the table we are interested in is the `states` table that is the primary storage location for entity state history. Understanding its structure is essential for working with raw data and statistics.

### Table Schema

### Used Fields

We only show the fields that are in use at the time of this writing. Other fields in the table are deprecated and should be ignored.

| Field                   | Type         | Description                                                                           |
| ------------------------- | -------------- | --------------------------------------------------------------------------------------- |
| `state_id`              | INTEGER      | Primary key, auto-incrementing unique identifier for each state record                |
| `metadata_id`           | INTEGER      | Foreign key to`states_meta` table (contains `entity_id` mapping)                      |
| `state`                 | VARCHAR(255) | The actual state value (e.g., "234.0", "on", "off", "23.5°C")                        |
| `last_updated_ts`       | FLOAT        | Unix timestamp when state was ***last updated*** (even if only attributes changed)  |
| `last_changed_ts`       | FLOAT        | Unix timestamp when the actual state **value changed** (NULL if same as`last_updated_ts`) |
| `last_reported_ts`      | FLOAT        | Unix timestamp when the state was last reported by the integration                    |
| `old_state_id`          | INTEGER      | Links to the previous`state_id` for this entity (enables state history traversal)     |
| `attributes_id`         | INTEGER      | Foreign key to`state_attributes` table (stored separately to avoid duplication)       |
| `context_id_bin`        | BLOB(16)     | Binary UUID identifying the context that caused this state change                     |
| `context_user_id_bin`   | BLOB(16)     | Binary UUID of the user who initiated the change (if applicable)                      |
| `context_parent_id_bin` | BLOB(16)     | Binary UUID of the parent context (for automation chains)                             |
| `origin_idx`            | SMALLINT     | Index indicating the origin of the state change                                       |

### Important Distinctions

- **`last_updated_ts`**: Changes when state OR attributes change
- **`last_changed_ts`**: Changes only when the state value itself changes. The `last_changed_ts` field is stored as NULL when it equals `last_updated_ts` to save database space
- **`last_reported_ts`**: The timestamp from the integration/device

### State Tracking for Statistics

The `states` table tracks all entity state changes, but in this document we focus specifically on "**statistical entities**" - those that generate **long-term statistics**. These entities belong to two main categories: the **measurement** type and the **total/counter** type (we'll explore these in detail in [Part 2](part2_statistics_generation.md#22-which-entities-generate-statistics)).

Let's examine how state tracking works with practical examples.

#### Example 1: Tracking Instantaneous Apparent Power Consumption (measurement type)

Consider an integration that polls the instantaneous apparent power consumption of a house every minute (a "measurement" type sensor). We can query the state history using:

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

Results

| entity_id           | state | last_updated    | last_changed    | last_reported   |
| --------------------- | ------- | ----------------- | ----------------- | ----------------- |
| sensor.linky_sinsts | 2040  | 1/27/2026 13:00 | 1/27/2026 13:00 | 1/27/2026 13:00 |
| sensor.linky_sinsts | 2030  | 1/27/2026 13:01 | 1/27/2026 13:01 | 1/27/2026 13:01 |
| sensor.linky_sinsts | 2023  | 1/27/2026 13:02 | 1/27/2026 13:02 | 1/27/2026 13:02 |
| ...                 | ...   | ...             | ...             | ...             |

Here we can see that we have a new state entry every minute (set by the integration).

#### Example 2: Tracking ZigBee Temperature Sensor (measurement type)

In contrast, a ZigBee temperature sensor reports values at intervals determined by the device itself, which may be irregular:

| entity_id                 | state | last_updated  | last_changed  | last_reported |
| --------------------------- | ------- | --------------- | --------------- | --------------- |
| sensor.family_temperature | 13.59 | 1/27/26 12:00 | 1/27/26 12:00 | 1/27/26 12:00 |
| sensor.family_temperature | 13.63 | 1/27/26 12:01 | 1/27/26 12:01 | 1/27/26 12:01 |
| sensor.family_temperature | 13.6  | 1/27/26 12:38 | 1/27/26 12:38 | 1/27/26 12:38 |
| sensor.family_temperature | 13.64 | 1/27/26 12:51 | 1/27/26 12:51 | 1/27/26 12:51 |

#### Example 3: Energy Meter (Total/Counter Type)

The two entities presented above belong to the **measurement** type, where we measure an instantaneous values that fluctuates up and down based on current conditions. We also have entities that belong to the **counter** type (e.g., energy consumption) where the state values are monotonically increasing:

| entity_id         | state    | last_updated    | last_changed    | last_reported   |
| ------------------- | ---------- | ----------------- | ----------------- | ----------------- |
| sensor.linky_east | 72199456 | 1/27/2026 12:59 | 1/27/2026 12:59 | 1/27/2026 12:59 |
| sensor.linky_east | 72199488 | 1/27/2026 13:00 | 1/27/2026 13:00 | 1/27/2026 13:00 |
| sensor.linky_east | 72199520 | 1/27/2026 13:01 | 1/27/2026 13:01 | 1/27/2026 13:01 |
| ...               | ...      | ...             | ...             | ...             |

Next

[Part 2: Statistics Generation](part2_statistics_generation.md)
