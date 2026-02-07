# Part 5: Find & Fix Statistics Errors

<TEXT>>

**Quick jump table**

| Error Type | Detection | Fix | Auto Fix |
| --- | --- | --- | --- |
| [Section Title](#51-section-title) | [sec_detect](#sec_detect) | [sec_fix](#sec_fix) | ❌ |
| [Invalid Data / Spikes](#52-invalid-data--spikes) | [spike_detect](#spike_detect) | [spike_fix](#spike_fix) | ✅ manual |

< TEXT >

## 5.1 Section Title

| [Description](#sec_description) | [Causes](#sec_causes) | [Manifestation](#sec_manifestation) | [Detection](#sec_detect) | [Fix](#sec_fix) |
| --- | --- | --- | --- | --- |

<a id="sec_description">**Description:**  
TEXT

<a id="sec_causes">**Causes:**
TEXT

<a id="sec_manifestation">**Manifestation**

< eventually if measurement and counter differ >
**Measurement entities:**
TEXT

**Counter entities:**
TEXT

<a id="sec_detect"></a>**Detection**
TEXT

<eventually if measurement and counter differ>
The SQL queries differs for [measurement](#sec_detect_measurement) and [counter](#sec_detect_counter) entities.

<a id="sec_detect_measurement"></a> **Detection for Measurement**
TEXT

<a id="sec_detect_counter"></a> **Detection for Counter**
TEXT

<a id="sec_fix">**Missing Statistics Fix**
TODO PLACEHOLDER

---

## 5.2 Invalid Data / Spikes
...