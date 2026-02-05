---
hide:
  - navigation
  - toc
---

<div class="hero">
  <div class="hero__inner">
    <h1 class="hero__title">Understanding and Using Home Assistant Statistics</h1>
    <p class="hero__subtitle">
      This site contains documents that explains how statistics are generated in Home Assistant (HA) and how to work with them effectively. It also provides SQL Examples on how to query the database.
    </p>
  </div>
</div>

<div class="home-columns">
  <div>
    <h2>Explore your data</h2>
    <p>
      Home Assistant stores a lot of information in its database. Statistics are the long-term, aggregated
      representation of that data and are used by many dashboards (notably Energy).
    </p>
    <p>
      These documents explain how statistics are produced, how to successfully use them, how to troubleshoot common issues. 
      We also presents many SQL queries examples to help you explore the Home Assistant database.
    </p>
  </div>
  <div>
    <h2>Documentation structure</h2>
    <p><a href="docs/doc/ha_statistics.md">Overview</a>: Start here to understand the big picture.</p>
    <p><a href="doc/part1_fundamental_concepts">Part 1</a>: Concepts: recorder, states, history, metadata.</p>
    <p><a href="doc/part2_statistics_generation">Part 2</a>: How statistics are computed and stored.</p>
    <p><a href="doc/part3_working_with_statistics">Part 3</a>: Working with Statistics.</p>
    <p><a href="doc/part4_practices_troubleshooting">Part 4</a>: Best practices and troubleshooting.</p>
    <p><a href="sql/sql_stat.md">SQL examples</a>: Practical queries for statistics and states.</p>
  </div>
</div>

## Start here

- [Overview](doc/ha_statistics.md)

## Sections

- [Part 1 - Foundational Concepts](doc/part1_fundamental_concepts.md)
- [Part 2 - Statistics Generation](doc/part2_statistics_generation.md)
- [Part 4 - Best Practices and Troubleshooting](doc/part4_practices_troubleshooting.md)

## Reference

- [Statistics Fields](doc/stat_fields.md)
- [Non-sensor Examples](doc/statistics_not_sensor.md)

## SQL

- [SQL - Statistics](sql/sql_stat.md)
- [SQL - States](sql/sql_states.md)
- [SQL - Tips](sql/sql_tips.md)
- [SQL - Python](sql/sql_python.md)
