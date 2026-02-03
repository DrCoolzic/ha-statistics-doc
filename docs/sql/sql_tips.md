# SQL Tips

- [SQL Tips](#sql-tips)
  - [SQLite MySQL Dialect Differences](#sqlite-mysql-dialect-differences)
    - [Conditional logic (CASE) - mostly the same](#conditional-logic-case---mostly-the-same)
    - [Grouping with aggregation](#grouping-with-aggregation)
  - [Portability Tips](#portability-tips)
    - [Most Portable (Works Everywhere)](#most-portable-works-everywhere)
    - [Less Portable (Database-Specific)](#less-portable-database-specific)
  - [JSON](#json)
    - [MySQL JSON extraction shorthand operators](#mysql-json-extraction-shorthand-operators)
    - [Extract Multiple Attributes (MySQL)](#extract-multiple-attributes-mysql)
    - [Filter by JSON Values (MySQL)](#filter-by-json-values-mysql)
    - [Cast to Numeric Type (MySQL)](#cast-to-numeric-type-mysql)
  - [Pattern Matching](#pattern-matching)
    - [Find all entities containing "temperature"](#find-all-entities-containing-temperature)
    - [Common pattern matching wildcards](#common-pattern-matching-wildcards)
    - [**Pattern Matching Examples**](#pattern-matching-examples)
  - [Usage of  SQL View](#usage-of--sql-view)
    - [Think of It Like a Shortcut](#think-of-it-like-a-shortcut)
    - [Key Characteristics of Views](#key-characteristics-of-views)
    - [Real-World Analogy](#real-world-analogy)
    - [When to Use Views](#when-to-use-views)
    - [View Operations](#view-operations)
    - [Example: Home Assistant Use Case](#example-home-assistant-use-case)
    - [Summary](#summary)

1. **Timestamps**: Home Assistant stores times as Unix timestamps (floating point). Use `datetime(timestamp, 'unixepoch', 'localtime')` to convert to readable dates.
2. **Entity relationships**: Always join `states` with `states_meta` to get the actual entity_id, and optionally with `state_attributes` for attributes.
3. **Performance**: For large databases, add `WHERE` clauses to limit time ranges, especially when querying states or events.
4. **JSON in attributes**: The `shared_attrs` field contains JSON data. In SQLite, you can parse it with `json_extract()` function.

---

## SQLite MySQL Dialect Differences

|                            | SQLite                                | MySQL/MariaDB                                                          |
| -------------------------- | ------------------------------------- | ---------------------------------------------------------------------- |
| Timestamp                  | `datetime(timestamp, 'unixepoch')`    |`FROM_UNIXTIME(timestamp)`                                              |
| String Concatenation       |`'Hello' ??`                           | `CONCAT('Hello', ' ', 'World')`                                        |
| Limit/Pagination           | `LIMIT 10 OFFSET 20`                  | `LIMIT 10 OFFSET 20`                                                   |
| Auto-increment Primary Key | `INTEGER PRIMARY KEY` (automatic)     | `AUTO_INCREMENT`                                                       |
| Boolean Type               | No native BOOLEAN, uses INTEGER (0/1) | `BOOLEAN` (stored as TINYINT)                                          |
| Case-Insensitive Search    | `LIKE` (case-insensitive by default)  | `LIKE` (case-insensitive) or `LIKE BINARY`                             |
| Now                        | SELECT datetime('now')                | SELECT NOW()                                                           |
| Adding days to a date      | SELECT datetime('now', '+7 days')     | SELECT DATE_ADD(NOW(), INTERVAL 7 DAY)                                 |
| String length              | SELECT length(column_name)            | SELECT LENGTH(column_name)  -- Same, but case matters in some contexts |

### Conditional logic (CASE) - mostly the same

```sql
-- Both SQLite and MariaDB (ANSI standard)
SELECT 
    CASE 
        WHEN value > 10 THEN 'high'
        ELSE 'low'
    END as category
```

### Grouping with aggregation

```sql
-- Both work the same for basic aggregates
SELECT category, COUNT(*), AVG(value)
FROM table
GROUP BY category
```

---

## Portability Tips

### Most Portable (Works Everywhere)

```sql
SELECT column1, column2
FROM table1
JOIN table2 ON table1.id = table2.id
WHERE column1 = 'value'
GROUP BY column1
ORDER BY column2
LIMIT 10
```

### Less Portable (Database-Specific)

- Date/time functions
- String manipulation
- Regular expressions
- Window functions (support varies)
- JSON operations
- Full-text search

---

## JSON

|                                                                 | SQLite          | MySQL/MariaDB                                  |
| --------------------------------------------------------------- | --------------- | ---------------------------------------------- |
| Get specific field                                              | json_extract()  | JSON_EXTRACT() or -> operator  or ->> operator |
| Iterate top level keys: returns table with key/value/type       | json_each()     | json_each()                                    |
| Iterate all nested paths: returns table with fullkey/path/value | json_tree()     | json_tree()                                    |
| Get keys                                                        | Use json_each() | json_keys()                                    |
| Format JSON nicely for display purposes                         | json_pretty()   | json_pretty()                                  |
| Get value type: 'text', 'integer', 'real', etc.                 | json_type()     | json_type()                                    |

### MySQL JSON extraction shorthand operators

  `->`  Returns JSON value (keeps quotes for strings)
  `->>`  Returns unquoted string/scalar value (recommended for most cases)

### Extract Multiple Attributes (MySQL)

```sql
SELECT 
    sm.entity_id,
    s.state,
    FROM_UNIXTIME(s.last_updated_ts) as last_updated,
    sa.shared_attrs->>'$.latitude' as latitude,
    sa.shared_attrs->>'$.longitude' as longitude,
    sa.shared_attrs->>'$.gps_accuracy' as gps_accuracy,
    sa.shared_attrs->>'$.source_type' as source_type,
    sa.shared_attrs->>'$.friendly_name' as friendly_name,
    sa.shared_attrs->>'$.battery_level' as battery_level
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC
LIMIT 20;
```

### Filter by JSON Values (MySQL)

```sql
SELECT 
    sm.entity_id,
    s.state,
    FROM_UNIXTIME(s.last_updated_ts) as last_updated,
    sa.shared_attrs->>'$.latitude' as latitude,
    sa.shared_attrs->>'$.longitude' as longitude
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_p620'
  AND JSON_EXTRACT(sa.shared_attrs, '$.latitude') IS NOT NULL
  AND s.state = 'not_home'
ORDER BY s.last_updated_ts DESC;
```

### Cast to Numeric Type (MySQL)

If you need to do math with the extracted values:

```sql
SELECT 
    sm.entity_id,
    FROM_UNIXTIME(s.last_updated_ts) as last_updated,
    CAST(sa.shared_attrs->>'$.latitude' AS DECIMAL(10, 6)) as latitude,
    CAST(sa.shared_attrs->>'$.longitude' AS DECIMAL(10, 6)) as longitude,
    CAST(sa.shared_attrs->>'$.gps_accuracy' AS UNSIGNED) as gps_accuracy
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC
LIMIT 20;
```

---

## Pattern Matching

### Find all entities containing "temperature"

```sql
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature%'
ORDER BY sm.entity_id;
```

### Common pattern matching wildcards

- `%` = matches any sequence of characters (including zero characters)
- `_` = matches exactly one character

### **Pattern Matching Examples**

#### Entities that START with "sensor.temperature"

```sql
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE 'sensor.temperature%'
ORDER BY sm.entity_id;
```

#### Entities that END with "temperature"

```sql
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature'
ORDER BY sm.entity_id;
```

#### Entities containing "temp" OR "temperature"

```sql
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temp%' 
   OR sm.entity_id LIKE '%temperature%'
ORDER BY sm.entity_id;
```

#### Case-insensitive matching (SQLite default behavior)

```sql
-- These will match "Temperature", "TEMPERATURE", "temperature", etc.
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE '%temperature%'sql
ORDER BY sm.entity_id;
```

#### Match exact pattern with underscore (single character wildcard)

```sql
-- Matches "sensor.temp_1", "sensor.temp_2", etc.
SELECT DISTINCT sm.entity_id
FROM states_meta sm
WHERE sm.entity_id LIKE 'sensor.temp_%'
ORDER BY sm.entity_id;
```

---

## Usage of  SQL View

A **view** in SQL is like a **saved query** that acts as a virtual table. It doesn't store data itself—it just stores the query definition and runs it whenever you access the view.

### Think of It Like a Shortcut

Instead of writing a complex query every time, you save it as a view and then query the view like it's a table.

#### Without a View (Long Query Every Time)

```sql
-- You have to write this complex query every time:
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    json_extract(sa.shared_attrs, '$.latitude') as latitude,
    json_extract(sa.shared_attrs, '$.longitude') as longitude
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id = 'device_tracker.sm_p620'
ORDER BY s.last_updated_ts DESC;
```

#### With a View (Simple Query)

```sql
-- Create the view once:
CREATE VIEW device_locations AS
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    json_extract(sa.shared_attrs, '$.latitude') as latitude,
    json_extract(sa.shared_attrs, '$.longitude') as longitude
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE sm.entity_id LIKE 'device_tracker.%';

-- Then query it like a regular table:
SELECT * FROM device_locations 
WHERE entity_id = 'device_tracker.sm_p620'
ORDER BY last_updated DESC
LIMIT 10;
```

### Key Characteristics of Views

| Aspect                 | Description                                |
| ---------------------- | ------------------------------------------ |
| **Virtual table**      | Looks like a table, but doesn't store data |
| **Always fresh**       | Shows current data from underlying tables  |
| **Simplifies queries** | Hide complex JOINs and calculations        |
| **Reusable**           | Write once, use many times                 |
| **No extra storage**   | Only stores the query definition           |
| **Performance**        | Same as running the underlying query       |

### Real-World Analogy

**View** = **Saved search/bookmark**

- A browser bookmark doesn't store the webpage
- It just stores the URL (the "query")
- When you click it, it fetches fresh content
- Same with views: they execute the query and show fresh data

### When to Use Views

#### ✅ Good Use Cases

1. **Simplify complex queries you use often**

   ```sql
   CREATE VIEW latest_temperatures AS
   SELECT 
       sm.entity_id,
       s.state as temperature,
       datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated
   FROM states s
   INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
   WHERE sm.entity_id LIKE 'sensor.%temperature%'
     AND s.state NOT IN ('unavailable', 'unknown');
   ```

2. **Security/permissions** - Show only certain columns to users

   ```sql
   CREATE VIEW public_device_status AS
   SELECT entity_id, state, last_updated_ts
   FROM states
   -- Excludes sensitive attributes
   ```

3. **Hide implementation details**

   ```sql
   CREATE VIEW energy_consumption AS
   SELECT 
       statistic_id,
       sum as total_kwh,
       datetime(start_ts, 'unixepoch') as date
   FROM statistics s
   INNER JOIN statistics_meta sm ON s.metadata_id = sm.id
   WHERE sm.unit_of_measurement = 'kWh';
   ```

#### ❌ When NOT to Use Views

1. **One-time queries** - Just run the query directly
2. **Very slow queries** - Views don't cache results; they recalculate every time
3. **Temporary exploration** - Use CTEs (`WITH` clause) instead

### View Operations

#### Create a View

```sql
CREATE VIEW my_view_name AS
SELECT ...;
```

#### Query a View

```sql
SELECT * FROM my_view_name WHERE ...;
```

#### See All Views

```sql
SELECT name FROM sqlite_master WHERE type = 'view';
```

#### See View Definition

```sql
SELECT sql FROM sqlite_master WHERE type = 'view' AND name = 'my_view_name';
```

#### Drop a View

```sql
DROP VIEW my_view_name;
```

#### Replace a View

```sql
DROP VIEW IF EXISTS my_view_name;
CREATE VIEW my_view_name AS
SELECT ...;
```

### Example: Home Assistant Use Case

Let's create a view for all entities with statistics:

```sql
CREATE VIEW entities_with_statistics AS
SELECT 
    sm.entity_id,
    s.state,
    datetime(s.last_updated_ts, 'unixepoch', 'localtime') as last_updated,
    json_extract(sa.shared_attrs, '$.state_class') as state_class,
    json_extract(sa.shared_attrs, '$.unit_of_measurement') as unit,
    json_extract(sa.shared_attrs, '$.device_class') as device_class
FROM states s
INNER JOIN states_meta sm ON s.metadata_id = sm.metadata_id
INNER JOIN (
    SELECT metadata_id, MAX(state_id) as max_state_id
    FROM states
    GROUP BY metadata_id
) latest ON s.metadata_id = latest.metadata_id AND s.state_id = latest.max_state_id
LEFT JOIN state_attributes sa ON s.attributes_id = sa.attributes_id
WHERE json_extract(sa.shared_attrs, '$.state_class') IS NOT NULL;
```

Now you can easily query it:

```sql
-- Get all energy sensors
SELECT * FROM entities_with_statistics 
WHERE device_class = 'energy';

-- Get all measurement sensors
SELECT * FROM entities_with_statistics 
WHERE state_class = 'measurement';

-- Get all sensors with no unit
SELECT * FROM entities_with_statistics 
WHERE unit IS NULL;
```

### Summary

**View** = Saved query that acts like a virtual table

- ✅ Simplifies complex queries
- ✅ Always shows fresh data
- ✅ No extra storage needed
- ✅ Makes repeated queries easier
- ❌ Doesn't cache/store results
- ❌ Can be slower if underlying query is complex

For Home Assistant database exploration, views are great for queries you run repeatedly (like "show me all statistics entities" or "show me all device tracker locations").
