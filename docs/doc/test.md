# Strange new behavior when changing unit_of_measurement

It seems that Home Assistant behaves strangely when you change the unit_of_measurement of a statistics sensor. This behavior, which seems strange to say the least, is very different from what happened before.

Here is the experiment I conducted:

Last night, in the integration I use to monitor my home's energy consumption, I changed the unit_of_measurement for a sensor from kilowatts to watts. Then I restarted the integration, but without restarting Home Assistant. In the states table, I can see this change.

| entity_id | state | last_changed | unit_of_measurement |
| --- | --- | --- | --- |
| sensor.linky_easf01 | 72789.046875 | 2026-02-07 23:20:10 | kWh |
| sensor.linky_easf01 | 72789.0703125 | 2026-02-07 23:21:11 | kWh |
| sensor.linky_easf01 | 72789.0859375 | 2026-02-07 23:22:10 | kWh |
| sensor.linky_easf01 | 72789.109375 | 2026-02-07 23:23:09 | kWh |
| sensor.linky_easf01 | unavailable | 2026-02-07 23:23:44 | kWh |
| sensor.linky_easf01 | 72789120.0 | 2026-02-07 23:24:01 | Wh |
| sensor.linky_easf01 | 72789144.0 | 2026-02-07 23:24:58 | Wh |
| sensor.linky_easf01 | 72789168.0 | 2026-02-07 23:25:57 | Wh |
| sensor.linky_easf01 | 72789184.0 | 2026-02-07 23:26:56 | Wh |
| sensor.linky_easf01 | 72789208.0 | 2026-02-07 23:27:57 | Wh |
| sensor.linky_easf01 | 72789224.0 | 2026-02-07 23:28:57 | Wh |
| sensor.linky_easf01 | 72789248.0 | 2026-02-07 23:29:58 | Wh |

We can see that at 23:23:44 the sensor becomes unavailable and the unit of measurement changes from kWh to Wh. Then at 23:24:01 the sensor value becomes available again and is multiplied by 1000. So far, the behavior seems logical in relation to the modification I made to the sensor.

Now, if I look at the statistics tables, I see that practically nothing has changed. In the statistics_meta table, there is no new entry with the same name and a different unit_of_measurement?

And if we look at the statistics_short_term table, practically nothing happens except that from 23:20:00 onwards, the sensor accuracy changes, which seems to indicate that Home Assistant is **automatically converting** the sensor values from Wh to kWh???

| statistic_id | period_start | state | sum |
| --- | --- | --- | --- |
| sensor.linky_easf01 | 2026-02-07 23:05:00 | 72788.8046875 | 883.484375 |
| sensor.linky_easf01 | 2026-02-07 23:10:00 | 72788.90625 | 883.5859375 |
| sensor.linky_easf01 | 2026-02-07 23:15:00 | 72789.015625 | 883.6953125 |
| sensor.linky_easf01 | 2026-02-07 23:20:00 | 72789.144 | 883.8236875000002 |
| sensor.linky_easf01 | 2026-02-07 23:25:00 | 72789.248 | 883.9276875000069 |
| sensor.linky_easf01 | 2026-02-07 23:30:00 | 72789.344 | 884.0236874999973 |
| sensor.linky_easf01 | 2026-02-07 23:35:00 | 72789.448 | 884.127687500004 |
| sensor.linky_easf01 | 2026-02-07 23:40:00 | 72789.552 | 884.231687499996 |


This morning, I restarted Home Assistant and the first surprise was that before the restart, the values were correctly displayed in Wh.

- At 09:00:35 (time of reboot), the sensor became unavailable and, inexplicably, its unit of measurement reverted to kWh.
- At 09:00:36, the sensor becomes available again and reverted back to recording the value in kWh, even though the integration continues to provide data in Wh ???

| entity_id | state | last_changed | unit_of_measurement |
| --- | --- | --- | --- |
| sensor.linky_easf01 | 72813296.0 | 2026-02-08 08:56:00 | Wh |
| sensor.linky_easf01 | 72813368.0 | 2026-02-08 08:56:59 | Wh |
| sensor.linky_easf01 | 72813440.0 | 2026-02-08 08:57:59 | Wh |
| sensor.linky_easf01 | 72813520.0 | 2026-02-08 08:59:00 | Wh |
| sensor.linky_easf01 | unavailable | 2026-02-08 09:00:35 | kWh |
| sensor.linky_easf01 | 72813.6 | 2026-02-08 09:00:36 | kWh |
| sensor.linky_easf01 | 72813.68 | 2026-02-08 09:00:58 | kWh |
| sensor.linky_easf01 | 72813.768 | 2026-02-08 09:02:00 | kWh |
| sensor.linky_easf01 | 72813.848 | 2026-02-08 09:02:59 | kWh |

I admit that I don't understand at all why Home Assistant, even though it receives information from a sensor in Wh, decides on its own to convert this data into kWh. 
It doesn't make any sense!

Now, if I look at the statistics_short_term table, it continues to behave as if nothing has changed. It continues, like the states table, to record information with the wrong unit of measurement ???

| statistic_id | period_start | state | sum |
| --- | --- | --- | --- |
| sensor.linky_easf01 | 2026-02-08 09:10:00 | 72814.704 | 909.3836874999979 |
| sensor.linky_easf01 | 2026-02-08 09:05:00 | 72814.312 | 908.9916875000054 |
| sensor.linky_easf01 | 2026-02-08 09:00:00 | 72813.928 | 908.6076874999999 |
| sensor.linky_easf01 | 2026-02-08 08:55:00 | 72813.52 | 908.1996875000041 |
| sensor.linky_easf01 | 2026-02-08 08:50:00 | 72813.216 | 907.8956875000003 |

This seems to be a completely different way of operating from what happened before, when there was a change in the unit of measurement, it was not processed in the states table, which only recorded the actual sensor data (vs converted data now).
As for the statistics, a new entry was created in the statistics_meta table with a different unit of measurement. The recording of the sensor with the old unit of measurement was stopped, and the recording of the sensor with the new unit of measurement was taking over.

I would like to know if there is a description somewhere of how Home Assistant behaves when the unit of measurement is changed? I chose a change that is easy to convert because it only requires multiplying by 1000, but what happens if the unit of measurement is changed from degrees Celsius to degrees Fahrenheit?

Are there any documents somewhere in the Home Assistant description that describe these behavioral changes?