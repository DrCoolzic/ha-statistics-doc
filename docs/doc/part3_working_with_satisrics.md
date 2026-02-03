## Part 3: Working with Statistics

### 3.1 Benefits of Statistics

- **Reduced storage**: Hourly aggregates vs. potentially hundreds of state changes
- **Faster queries**: Pre-aggregated data loads much faster
- **Long-term retention**: Keep years of trend data without massive databases
- **Energy dashboard**: Powers the built-in energy monitoring features

### 3.2 Accessing Statistics

#### Via the UI

- [Developer Tools](https://www.home-assistant.io/docs/tools/dev-tools/) → Statistics
  Shows all recorded statistics in a table and allow to fix some problems.
- Energy Dashboard (for energy entities)
- [History panels](https://www.home-assistant.io/integrations/history/)

- [History graphs](https://www.home-assistant.io/dashboards/history-graph/)
  Is used to display **measurement** type statistics. It uses short term statistics to show detailed information (5 minutes sampling) during the retention period and long term statistic (1 hour sampling) for longer period.
  ![measurement](../resources/history_graph.png)
- [Statistics graph card](https://www.home-assistant.io/dashboards/statistics-graph)
  It uses long term statistics to display **measurement** or **counter** type statistics.
  - For measurement it can display the min, max, and mean information. In this case the chart type is usually set to line
  ![measurement](../resources\measure_stat.png)
  - For counter it can display the state, sum, and delta change. To display change the chart type is usually set to bar and for sum it is set to line. Note that the sum displayed in period is not what is stored in the table as it always start at 0. This allow to more easily  read the consumption over the period.
  ![counter_change](D:\Projects\ha\HA Statistics\resources\counter_change.png) ![counter_sum](D:\Projects\ha\HA Statistics\resources\counter_sum.png)

- And many custom card

#### Via Services

- `recorder.get_statistics`: retrieve statistics for entities over a specified period

#### Via Database

For advanced analysis and custom integrations it can be useful to perform Direct SQL queries of `statistics` and `statistics_short_term` tables. This can be done using the SQLite web addon (if you use SQLite DB) or the phpMyAdmin addon (if you are using MariaDB). It is also possible to query the database directly from a python program.
Here are some examples of queries:

- [Useful SQL Queries for accessing States & Attributes](../sql/sql_state.md)
- [Useful SQL Queries for Accessing Statistics](../sql/sql_stat.md)
- [SQL Tips](../sql/sql_tips.md)

[Basic information on accessing statistics directly from Python](../sql/sql_python.md)

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