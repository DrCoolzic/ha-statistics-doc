# Part 1: Foundational Concepts

## 1.1 Home Assistant Core Behavior

Home Assistant Core is an **event-driven application** that maintains real-time state for all entities in your system. Understanding this architecture is crucial to understanding how statistics are derived. We first look at some key concepts.

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

> **Further Reading**: For more details, see the [Core Architecture](https://developers.home-assistant.io/docs/architecture_index), [Sensor  entity](https://developers.home-assistant.io/docs/core/entity/sensor/), [Entities: integrating devices & services](https://developers.home-assistant.io/docs/architecture/devices-and-services/), and [States](https://developers.home-assistant.io/docs/dev_101_states/) documentation.

---

## 1.2 The Recorder Integration

The Recorder integration stores historical data about your system in a database, enabling you to track how states change over time.

### Sampling and Storage

- Objects are **sampled every 5 seconds** by default (configurable)
- Values are **committed to the database only if they are valid and if they have changed**
- This 5-second interval balances responsiveness with storage efficiency. According to the Nyquist-Shannon sampling theorem, a 5-second sampling rate can accurately capture changes that occur at intervals of 10 seconds or longer. For faster-changing values, intermediate states may not be captured, though the system will still record the value present at each 5-second sample.

### Database Backend

- **Default**: SQLite (suitable for most installations)
- **Alternatives**: PostgreSQL, MySQL/MariaDB (for advanced setups with high write volumes)

> **Further Reading**: See the [Database Schema documentation](https://www.home-assistant.io/docs/backend/database/#schema) for complete table descriptions.

---

## 1.3 The States Table

The Recorder Integration writes to numerous tables in the database, but in the context of this document, the table we are interested in is the `states` table that is the primary storage location for entity state history. Understanding its structure is essential for working with raw data and statistics.

### Table Schema

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

- **`last_updated_ts`**: Unix timestamp  when state OR attributes change
- **`last_changed_ts`**: Unix timestamp when the actual state **value changed** (stored as NULL when it equals `last_updated_ts` to save database space)
- **`last_reported_ts`**: Unix timestamp from the integration/device

---

## 1.4 Entities Generating Statistics

The `states` table tracks **all** entities, but in this document we focus specifically on "**statistics**" entities - those that generate **long-term statistics**.
These entities belong to two main categories (we'll explore these in detail in [Part 2](part2_statistics_generation.md#22-which-entities-generate-statistics)):

- the **measurement** type
- the **total/counter** type .

> **Note on Data Retention:** While statistics are retained long-term, the detailed state history in the `states` table is typically purged after a configurable period (default: 10 days). This is why statistics are essential for long-term trend analysis.

Let's examine how state tracking works with practical examples.

## 1.5 Examples tracking statistics

### Apparent Power Consumption

Consider an integration that polls the instantaneous apparent power consumption (a "measurement" type sensor) of a house every minute .

| entity_id           | state | last_updated    | last_changed    | last_reported   |
| --------------------- | ------- | ----------------- | ----------------- | ----------------- |
| sensor.linky_sinsts | 2040  | 1/27/2026 13:00 | 1/27/2026 13:00 | 1/27/2026 13:00 |
| sensor.linky_sinsts | 2030  | 1/27/2026 13:01 | 1/27/2026 13:01 | 1/27/2026 13:01 |
| sensor.linky_sinsts | 2023  | 1/27/2026 13:02 | 1/27/2026 13:02 | 1/27/2026 13:02 |
| ...                 | ...   | ...             | ...             | ...             |

### ZigBee Temperature Sensor

In contrast, a ZigBee temperature sensor (a "measurement" type sensor) reports values at intervals determined by the device itself, which may be irregular:

| entity_id                 | state | last_updated  | last_changed  | last_reported |
| --------------------------- | ------- | --------------- | --------------- | --------------- |
| sensor.family_temperature | 13.59 | 1/27/26 12:00 | 1/27/26 12:00 | 1/27/26 12:00 |
| sensor.family_temperature | 13.63 | 1/27/26 12:01 | 1/27/26 12:01 | 1/27/26 12:01 |
| sensor.family_temperature | 13.6  | 1/27/26 12:38 | 1/27/26 12:38 | 1/27/26 12:38 |
| sensor.family_temperature | 13.64 | 1/27/26 12:51 | 1/27/26 12:51 | 1/27/26 12:51 |

### Energy Meter

The two entities presented above generates statistics that belong to the **measurement** type. This example belongs to the **counter** type (e.g., energy consumption) where the state values are monotonically increasing:

| entity_id         | state    | last_updated    | last_changed    | last_reported   |
| ------------------- | ---------- | ----------------- | ----------------- | ----------------- |
| sensor.linky_east | 72199456 | 1/27/2026 12:59 | 1/27/2026 12:59 | 1/27/2026 12:59 |
| sensor.linky_east | 72199488 | 1/27/2026 13:00 | 1/27/2026 13:00 | 1/27/2026 13:00 |
| sensor.linky_east | 72199520 | 1/27/2026 13:01 | 1/27/2026 13:01 | 1/27/2026 13:01 |
| ...               | ...      | ...             | ...             | ...             |

<div class="nav-prevnext" markdown="0">
  <a href="../overview/" class="nav-prev">
    <span class="nav-label">Previous</span>
    <span class="nav-title">« Overview</span>
  </a>
  <a href="../part2_statistics_generation/" class="nav-next">
    <span class="nav-label">Next</span>
    <span class="nav-title">Part 2: Statistics Generation »</span>
  </a>
</div>
