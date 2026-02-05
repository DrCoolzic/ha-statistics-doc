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
  commit_interval: 10  # Commit to DB every 10 second
  # Note: Statistics have separate retention:
  # - Short-term statistics auto-purge after 10 days
  # - Long-term statistics kept indefinitely unless manually purged
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

## 4.4 Troubleshooting

### Common Issues & Solutions

| **Issue**                     | **Cause**                      | **Solution**                                        |
| ------------------------------- | -------------------------------- | ----------------------------------------------------- |
| No statistics at all          | Missing`state_class`           | Add`state_class: measurement` or `total_increasing` |
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
