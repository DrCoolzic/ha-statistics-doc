# Understanding and Using Home Assistant Statistics

## Who Should Read This Document

This guide is for Home Assistant users who want to:

- Understand how their data is stored and aggregated
- Optimize database performance and storage
- Create custom statistics or troubleshoot existing ones
- Build advanced dashboards using historical data
- Migrate or manipulate statistics data

## Overview

This document explains how statistics are generated in Home Assistant (HA) and how to work with them effectively. Statistics provide aggregated, long-term data storage that is more efficient than raw state history, making them essential for tracking trends, creating dashboards, and analyzing system behavior over time.

Before diving into statistics themselves, we'll explore how HA Core and the Recorder integration work, as these form the foundation for statistics generation.

---

## [Part 1: Foundational Concepts](part1_fundamental_concepts.md)

Establishes the foundation for understanding Home Assistant statistics by explaining how HA Core works as an event-driven system. Covers:

- How entities, states, and events form the basis of HA's real-time monitoring
- The Recorder integration's role in sampling and storing state changes every 5 seconds
- The structure of the `states` table and key timestamp fields (`last_updated_ts`, `last_changed_ts`, `last_reported_ts`)
- Practical examples showing how different sensor types (power meters, temperature sensors, energy counters) are tracked in the states table

This part is essential reading for understanding where statistics data originates and how raw state data differs from aggregated statistics.

---

## [Part 2: Statistics Generation](part2_statistics_generation.md)

Explains how Home Assistant transforms raw state data into efficient, long-term statistics. Covers:

- The difference between short-term (5-minute) and long-term (1-hour) statistics
- Which entities generate statistics: **measurement** types (tracking min/max/mean) and **counter** types (tracking sum and state)
- How statistics are computed:
  - Arithmetic and circular mean calculations for measurements
  - Sum accumulation and reset detection for counters
  - Special handling for `total_increasing` (monotonic) vs. `total` (bidirectional) counters
- The structure of `statistics_meta`, `statistics`, and `statistics_short_term` tables
- Complete data flow from entity states through the statistics compiler to database storage
- Detailed examples showing how statistics are generated for real sensors

Essential for understanding which `state_class` to use and how your data will be aggregated.

---

## [Part 3: Working with Statistics](part3_working_with_statistics.md)

Provides practical guidance on accessing and using statistics in Home Assistant. Covers:

- Benefits of statistics: reduced storage, faster queries, long-term retention
- Common use cases: energy monitoring, temperature trends, cost tracking, performance analysis
- How to access statistics:
  - Through the UI: Developer Tools, Energy Dashboard, History panels, Statistics/History graph cards
  - Via services: `recorder.get_statistics`
  - Via direct database queries: SQL examples and database tools
- Visual examples of different graph types for measurement and counter statistics

This part helps you leverage statistics for dashboards, analysis, and custom integrations.

---

## [Part 4: Best Practices and Troubleshooting](part4_practices_troubleshooting.md)

Offers actionable guidance for configuring statistics correctly and resolving common issues. Covers:

- Quick reference table for choosing the correct `state_class` based on what you want to track
- Visual troubleshooting decision tree for diagnosing statistics problems
- Recorder configuration recommendations for optimal performance
- Statistics limitations and how to work within them
- Common issues and solutions: missing statistics, incorrect values, performance problems
- Using Developer Tools → Statistics for validation and repair
- Best practices for database purging, entity filtering, and migration

Critical for ensuring your statistics configuration is correct and maintaining system performance over time.

## [Part 5: Find & Fix Statistics Errors](part4_practices_troubleshooting.md)

TODO Summary

## [Quick Reference Guide](quick_reference_guide.md)

## [Glossary](glossary.md)

## Conclusion

Statistics in Home Assistant provide an efficient way to store and analyze long-term trends while managing storage constraints. By understanding the relationship between states, the recorder, and statistics generation, you can make informed decisions about what to track and how to optimize your system's performance.

**Key Takeaways**

1. States capture every change; statistics aggregate them efficiently
2. State class determines how statistics are calculated
3. Short-term and long-term statistics balance detail with storage
4. Proper configuration prevents both storage bloat and data loss

---

## References

### [Home Assistant Documentation](https://www.home-assistant.io/docs/)

- [Events](https://www.home-assistant.io/docs/configuration/events/)
- [Entities and domains](https://www.home-assistant.io/docs/configuration/entities_domains/)
- [Database](https://www.home-assistant.io/docs/backend/database/)
- [Recorder integration](https://www.home-assistant.io/integrations/recorder/)
- [History integration](https://www.home-assistant.io/integrations/history/)

### Home Assistant Developer Docs

- [Sensor entity](https://developers.home-assistant.io/docs/core/entity/sensor)
- [Core architecture](https://developers.home-assistant.io/docs/architecture/core/)
- [Long Term Statistics](https://developers.home-assistant.io/docs/core/entity/sensor/#long-term-statistics)

### Home Assistant Data Science Portal

- [Long- and short-term statistics](https://data.home-assistant.io/docs/statistics/)
- [Home Assistant Recorder Runs](https://data.home-assistant.io/docs/recorder/)

### Community Resources

- [Taming my Home Assistant database growth - Koskila.net](https://www.koskila.net/taming-my-home-assistant-database-growth/)
- [Loading, Manipulating, Recovering and Moving Long Term Statistics](https://community.home-assistant.io/t/loading-manipulating-recovering-and-moving-long-term-statistics-in-home-assistant/953802)
- [Mastering Home Assistant's Recorder and History](https://newerest.space/mastering-home-assistant-recorder-history-optimization/)
