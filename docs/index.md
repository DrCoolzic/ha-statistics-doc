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
    <h2>About this site</h2>
    <p>
      Home Assistant stores a wealth of information in its database. <strong>Statistics</strong> are the long-term, aggregated
      representation of that data, used by many dashboards — most notably the Energy dashboard.
    </p>
    <p>
      This documentation covers everything you need to know about statistics: how they are generated, how to configure sensors correctly, how to troubleshoot and fix common issues, and how to query the database directly with SQL.
    </p>
    <p>
      Whether you are trying to understand why your energy dashboard shows wrong values, need to change a sensor's unit of measurement, or want to explore your data with SQL — you'll find the answer here.
    </p>
    <h3>Who is this for?</h3>
    <ul>
      <li><strong>HA users</strong> who want to understand how statistics work behind the scenes</li>
      <li><strong>Troubleshooters</strong> dealing with missing data, spikes, or incorrect values</li>
      <li><strong>Power users</strong> who want to query and manipulate the database directly</li>
    </ul>
    <h3>Important notes</h3>
    <p>This documentation is based on Home Assistant documents and thorough testing, so it should be relatively accurate. However, it will inevitably contain errors or omissions — HA evolves quickly and some behaviors are not well documented.</p>
  </div>
  <div>
    <h2>Documentation structure</h2>
    <p><a href="doc/overview"><strong>Overview  ← Start here</strong></a><br/>
    A high-level map of all documentation sections and what they cover.</p>
    <p><a href="doc/part1_fundamental_concepts"><strong>Part 1 — Foundational Concepts</strong></a><br/>
    Entities, states, the recorder, and how they relate to statistics.</p>
    <p><a href="doc/part2_statistics_generation"><strong>Part 2 — Statistics Generation</strong></a><br/>
    How HA compiles short-term and long-term statistics from sensor data.</p>
    <p><a href="doc/part3_working_with_statistics"><strong>Part 3 — Working with Statistics</strong></a><br/>
    Dashboards, graphs, and how statistics are displayed in the UI.</p>
    <p><a href="doc/part4_practices_troubleshooting"><strong>Part 4 — Best Practices & Troubleshooting</strong></a><br/>
    Choosing the right state_class, recorder configuration, and common pitfalls.</p>
    <p><a href="doc/part5_find_fix"><strong>Part 5 — Find & Fix Statistics Errors</strong></a><br/>
    Detect and repair data gaps, spikes, orphaned entries, counter resets, and more.</p>
    <p><a href="doc/apdx1_stat_fields"><strong>Appendix 1 — Mysterious Table Fields</strong></a><br/>
    Deep dive into <code>created_ts</code> and <code>mean_weight</code> fields.</p>
    <p><a href="doc/apdx2_stat_domains"><strong>Appendix 2 — Statistics Domains</strong></a><br/>
    Examples of statistics from non-sensor domains (number, input_number, counter).</p>
    <!-- <p><a href="doc/apdx3_set_units"><strong>Appendix 3 — Units of Measurement</strong></a><br/>
    How HA selects, stores, and displays units — and how to control them.</p>
    <p><a href="doc/apdx4_change_units"><strong>Appendix 4 — Changing Units</strong></a><br/>
    Step-by-step guide to changing units on sensors that already have statistics.</p> -->
    <p><a href="doc/quick_reference_guide"><strong>Quick Reference Guide</strong></a><br/>
    Cheat sheet with key concepts, common queries, and decision tables at a glance.</p>
    <hr/>
    <p><a href="sql/sql_overview"><strong>SQL Examples</strong></a><br/>
    Ready-to-use queries for statistics, states, and error detection.</p>
  </div>
</div>
