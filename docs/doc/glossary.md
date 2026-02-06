# Glossary

**Created Timestamp (`created_ts`)**: Unix timestamp when Home Assistant wrote the statistics record to the database

**Measurement Type**: Statistics that track min/max/mean of a value that represents a point-in-time measurement

**Metadata ID**: Foreign key linking statistics records to their definition in `statistics_meta`

**Recorder Integration**: The HA component responsible for writing entity states to the database

**State Class**: Entity attribute (`measurement`, `total`, `total_increasing`) that determines how statistics are calculated

**Statistic ID**: Unique identifier for a statistics series, usually matching the entity_id

**Statistics Compiler**: Background process that aggregates state changes into statistics every 5 minutes (short-term) and hourly (long-term)

**Total Type**: Statistics that track cumulative values (counters) rather than point-in-time measurements