# Migration of counter entities from old to new system

## data in old system

old system has started at an earlier date with a state of 90000 that was used as a base for the sum.

| entity_id | start_time | state | sum | delta |
| --- | --- | --- | --- | --- |
| ... | ... | ... | ... | ... |
| sensor.linky_east | 2026-02-15 18:00:00 | 100000 | 10000 | - |
| sensor.linky_east | 2026-02-15 19:00:00 | 100010 | 10010 | 10 |
| sensor.linky_east | 2026-02-15 20:00:00 | 100020 | 10020 | 10 |
| sensor.linky_west | 2026-02-15 21:00:00 | 100040 | 10040 | 20 |
| sensor.linky_west | 2026-02-15 22:00:00 | 100050 | 10050 | 10 |
| sensor.linky_west | 2026-02-15 22:00:00 | 100060 | 10060 | 10 |

## data in new system

new system has started at a later date when state was at 99000 that was used as a base for the sum.

| entity_id | start_time | state | sum | delta |
| --- | --- | --- | --- | --- |
| ... | ... | ... | ... | ... |
| sensor.linky_west | 2026-02-15 21:00:00 | 100040 | 1040 | - |
| sensor.linky_west | 2026-02-15 22:00:00 | 100050 | 1050 | 10 |
| sensor.linky_west | 2026-02-15 23:00:00 | 100060 | 1060 | 10 |
| sensor.linky_west | 2026-02-15 24:00:00 | 100090 | 1090 | 30 |

## expected after migration

For migration import to work we need to wait for the new system to have an more entry than the old system. Otherwise even if we enter correct values in the statistics table, as the values in the statistics_short_term table are still wrong this will they will produce wrong results for the next entry in the statistics table.

After importing the "migration data" we expect the following data.

| entity_id | start_time | state | sum | delta |
| --- | --- | --- | --- | --- |
| sensor.linky_east | 2026-02-15 18:00:00 | 100000 | 1000 | - |
| sensor.linky_east | 2026-02-15 19:00:00 | 100010 | 1010 | 10 |
| sensor.linky_east | 2026-02-15 20:00:00 | 100020 | 1020 | 10 |
| sensor.linky_west | 2026-02-15 21:00:00 | 100040 | 1040 | 20 |
| sensor.linky_west | 2026-02-15 22:00:00 | 100050 | 1050 | 10 |
| sensor.linky_west | 2026-02-15 23:00:00 | 100060 | 1060 | 10 |
| sensor.linky_west | 2026-02-15 24:00:00 | 100090 | 1090 | 30 |

