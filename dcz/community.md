# to publish in Community Guide https://community.home-assistant.io/c/community-guides/51

Tags: database statistics guide howto recorder documentation cookbook

Title: Understand and Use Home Assistant Statistics

---

## Introduction

I am currently working on an integration for Home Assistant that makes extensive use of statistics. Over the past few weeks, I have been reviewing all the information I could find on this subject — official documentation, developer sources, community posts — and conducting numerous experiments to better understand how statistics actually work under the hood.

I usually record information as I collect it, so I have created a comprehensive set of documents that I think might be of interest to others in the community. Whether you are trying to understand why your energy dashboard shows wrong values, need to change a sensor's unit of measurement, or want to explore your database with SQL — this documentation should help.

### What's covered

The documentation is organized into **five main parts** plus appendices and SQL examples:

- **Part 1 — Foundational Concepts**: How HA Core works as an event-driven system, entities, states, the Recorder integration, and the `states` table structure
- **Part 2 — Statistics Generation**: How raw state data is transformed into short-term (5-minute) and long-term (1-hour) statistics, measurement vs counter types, mean calculations, sum accumulation, and the database schema
- **Part 3 — Working with Statistics**: How to access statistics through the UI (Developer Tools, Energy Dashboard, History/Statistics graph cards), via services, and through direct SQL queries
- **Part 4 — Best Practices & Troubleshooting**: Choosing the right `state_class`, recorder configuration, common pitfalls, and a troubleshooting decision tree
- **Part 5 — Find & Fix Statistics Errors**: Detecting and repairing data gaps, spikes, orphaned entries, renamed entities, counter reset failures, wrong mean types, and more — with SQL queries and step-by-step fix instructions

Additional documents available on the repository:

- **Appendix 1** — Deep dive into the mysterious `created_ts` and `mean_weight` fields
- **Appendix 2** — Examples of statistics from non-sensor domains (number, input_number, counter)
- **Appendix 3** — How HA selects, stores, and displays units of measurement
- **Appendix 4** — Step-by-step guide to changing units on sensors with existing statistics
- **SQL Examples** — Ready-to-use queries for states, statistics, and error detection

*For now ignore the appendices 3 and 4 about units of measurement. I thought I had them ready but each time I experiment with them I find something else that breaks them. This is specialy true for changing units on sensors...*

### Where to find the documentation

I have created a GitHub repository with all the documents. You can read them:

- **As a website** (recommended): https://drcoolzic.github.io/ha-statistics-doc/
- **As Markdown on GitHub**: https://github.com/DrCoolzic/ha-statistics-doc

### Important notes

This documentation is based on Home Assistant documents and thorough testing, so it should be relatively accurate. However, it will inevitably contain errors or omissions — HA evolves quickly and some behaviors are not well documented.

I will try, depending on the time I have available, to answer questions and correct errors. **To avoid duplicating work, only the overview will be published in the community guide** Only the documents in the GitHub repository will be maintained. If you want the latest version, always consult the repository.

Contributions, corrections, and suggestions are welcome — feel free to open an issue or pull request on GitHub.

---

I will publish each part as a separate reply below. Enjoy! :books:
