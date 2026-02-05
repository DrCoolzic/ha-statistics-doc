# Part 4: Best Practices and Troubleshooting

## 4.1 State Class Selection Guide

Use this table to quickly determine which `state_class` to use for your entity:

| **I want to track...**               | **Use state_class**                     | **Tracks**              | **Example**               | **Graph Shows**              |
| -------------------------------------- | ----------------------------------------- | ------------------------- | --------------------------- | ------------------------------ |
| Current temperature                  | `measurement`                           | mean, min, max, state   | Temperature sensor        | Average temp over time       |
| Current humidity                     | `measurement`                           | mean, min, max, state   | Humidity sensor           | Min/max/avg humidity         |
| Current power usage                  | `measurement`                           | mean, min, max, state   | Power meter               | Real-time wattage trends     |
| Wind direction                       | `measurement_angle`                     | circular mean, min, max | Wind compass              | Average direction (circular) |
| Total energy consumed (never resets) | `total_increasing`                      | state, sum              | Lifetime energy meter     | Cumulative consumption       |
| Energy meter (may reset)             | `total_increasing`                      | state, sum              | Monthly energy meter      | Handles meter resets         |
| Net energy (can go +/-)              | `total` with `last_reset`               | state, sum              | Solar net metering        | Bidirectional flow           |
| Differential energy readings         | `total` + update `last_reset` each time | state, sum              | "Last minute consumption" | Each reading as delta        |
| Binary sensor (on/off only)   | None (no `state_class`)              | -                       | Door sensor               | State history only       |
| Diagnostic data (not trends)  | None (no `state_class`)              | -                       | Firmware version          | No statistics needed     |

**Key Decision Points:**

- Does the value represent a **current moment** (temperature, power now)? → `measurement`
- Is it an **angle/direction**? → `measurement_angle`
- Does it **only increase** (or reset to zero)? → `total_increasing`
- Can it **increase AND decrease**? → `total` with `last_reset`

---

**Troubleshooting Decision Tree**

```text
┌─────────────────────────────────────┐
│  Statistics not showing for entity? │
└─────────────┬───────────────────────┘
              │
              ├─ NO state_class set? ───────────> Add state_class attribute
              │
              ├─ state_class exists?
              │   │
              │   ├─ Check unit_of_measurement
              │   │   │
              │   │   ├─ Missing? ─────────────> Add unit (e.g., "kWh", "°C")
              │   │   └─ Present?
              │   │
              │   ├─ Check if entity is excluded in recorder config
              │   │   │
              │   │   ├─ Excluded? ──────────> Remove from exclude list
              │   │   └─ Not excluded?
              │   │
              │   ├─ Check state values in states table
              │   │   │
              │   │   ├─ States = "unavailable" or "unknown"? ──> Fix integration
              │   │   ├─ States = non-numeric? ──────────────> Check sensor output
              │   │   └─ States = numeric? ──────────────────> Check next step
              │   │
              │   └─ Check Developer Tools → Statistics
              │       │
              │       └─ Shows errors? ──────────────────────> Read error message
              │
              └─ Statistics exist but values wrong?
                  │
                  ├─ For totals/counters: Use recorder.adjust_sum service
                  ├─ Unit changed mid-stream? ─────────────> Creates new statistic_id
                  └─ Meter replaced? ──────────────────────> Use recorder.adjust_sum
```

## 4.2 Recorder Configuration Recommendations

### Purge Settings

Adjust recorder purge settings based on your storage capacity:

```yaml
recorder:
  purge_keep_days: 7  # Keep detailed states for 7 days
  commit_interval: 10  # Commit to DB every 10 seconds
# Note: Statistics have separate retention:
# - Short-term statistics: auto-purge after 10 days (default, configurable via auto_purge)
# - Long-term statistics: kept indefinitely unless manually purged
```

### Include/Exclude Entities

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

## 4.3 Statistics Limitations

- **No retroactive generation**: Statistics are only generated going forward
- **Missing data handling**: Gaps in state data create gaps in statistics
- **State class changes**: Changing state class doesn't recalculate existing statistics
- **Precision**: Aggregation inherently loses detail compared to raw states
- **Statistics repair**: Home Assistant includes automatic repair mechanisms for some common issues (e.g., unit conversion, duplicate statistics). Check Settings → System → Repairs.

## 4.4 Troubleshooting

### Common Issues & Solutions

| **Issue**                     | **Cause**                      | **Solution**                                        |
| ------------------------------- | -------------------------------- | ----------------------------------------------------- |
| No statistics at all          | Missing `state_class`         | Add `state_class: measurement` or `total_increasing` |
| Statistics stopped generating | Entity excluded from recorder  | Check`recorder:` config exclude/include             |
| Wrong values in sum           | Meter replacement/reset        | Use`recorder.adjust_sum` service                    |
| Statistics reset unexpectedly | Unit changed (e.g., Wh → kWh) | New statistic_id created; use consistent units      |
| Missing historical stats      | `state_class` added recently   | Statistics only generated going forward             |

### Missing Statistics

- Verify entity has `state_class` attribute
- Check entity provides numerical values
- Ensure recorder is including the entity
- Check Developer Tools → Statistics for errors

### Incorrect Values

- Use `recorder.adjust_sum` service to fix cumulative totals
- Check for unit conversions in entity attributes
- Verify state changes are being recorded in `states` table

### Performance Issues

- Reduce `purge_keep_days` to limit database size
- Consider migrating to PostgreSQL for large installations
- Exclude unnecessary entities from recording

### Developer Tools → Statistics Tab

This powerful tool shows:

- All entities generating statistics
- Validation issues (unit changes, duplicates, etc.)
- Ability to fix some issues directly (e.g., adjust sum values)

**Common validation issues:**

- "Entity has a new unit" - unit of measurement changed
- "Detected duplicates" - multiple statistics for the same period
- "Entity has a new statistic ID" - state_class or source changed

## 4.5 Migrating and Backing Up Statistics

### Backing Up Statistics

- Statistics are stored in the main database (`home-assistant_v2.db` for SQLite)
- Standard HA backups include the database
- For selective statistics backup, export the `statistics`, `statistics_short_term`, and `statistics_meta` tables

### Migrating Statistics

When changing databases (e.g., SQLite → PostgreSQL):

1. Use the built-in database migration tools in HA
2. Verify statistics after migration using Developer Tools → Statistics
3. Check for any validation errors or missing data

### Exporting Statistics

For analysis in external tools:

- Export via SQL queries to CSV
- Use the `recorder.statistics_during_period` service
- Consider tools like [InfluxDB integration](https://www.home-assistant.io/integrations/influxdb/) for dedicated time-series databases

**Previous** - [Part 3: Working with Statistics](part3_working_with_statistics.md)
