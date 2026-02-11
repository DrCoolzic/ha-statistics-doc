# Understanding and Using Home Assistant Statistics

A comprehensive documentation site explaining how statistics are generated, stored, and used in Home Assistant. Includes practical SQL query examples for exploring and troubleshooting the database.

## Published Site

<https://drcoolzic.github.io/ha-statistics-doc/>

## Documentation Structure

### Statistics Documentation

| Section | Description |
|---------|-------------|
| [Overview](./docs/doc/overview.md) | High-level map of all documentation sections |
| [Part 1 — Foundational Concepts](./docs/doc/part1_fundamental_concepts.md) | Entities, states, the recorder, and how they relate to statistics |
| [Part 2 — Statistics Generation](./docs/doc/part2_statistics_generation.md) | How HA compiles short-term and long-term statistics |
| [Part 3 — Working with Statistics](./docs/doc/part3_working_with_statistics.md) | Dashboards, graphs, and UI display |
| [Part 4 — Best Practices & Troubleshooting](./docs/doc/part4_practices_troubleshooting.md) | Choosing state_class, recorder config, common pitfalls |
| [Part 5 — Find & Fix Statistics Errors](./docs/doc/part5_find_fix.md) | Detect and repair data gaps, spikes, orphaned entries, and more |
| [Appendix 1 — Mysterious Table Fields](./docs/doc/apdx1_stat_fields.md) | Deep dive into `created_ts` and `mean_weight` |
| [Appendix 2 — Statistics Domains](./docs/doc/apdx2_stat_domains.md) | Statistics from non-sensor domains |
| [Quick Reference Guide](./docs/doc/quick_reference_guide.md) | Cheat sheet with key concepts and decision tables |
| [Glossary](./docs/doc/glossary.md) | Terminology reference |

### SQL Examples

| Section | Description |
|---------|-------------|
| [States Queries](./docs/sql/sql_states.md) | Querying the states and states_meta tables |
| [Statistics Queries](./docs/sql/sql_statistics.md) | Querying statistics and statistics_short_term tables |
| [Error Detection Queries](./docs/sql/sql_errors.md) | SQL queries to detect common statistics errors |
| [SQL Tips](./docs/sql/sql_tips.md) | Useful SQLite/MariaDB tips and techniques |

## Building Locally

The site is built with [MkDocs](https://www.mkdocs.org/) using the [Material](https://squidfunk.github.io/mkdocs-material/) theme.

```bash
pip install mkdocs-material
mkdocs serve
```

Then open <http://127.0.0.1:8000> in your browser.

## License

This project is licensed under the [MIT License](./LICENSE).
