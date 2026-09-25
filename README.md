# legacy-registration-data-pipeline

> **End-to-end SQL pipeline reconciling 3 fragmented legacy tables (registrant, eligibility, graduation) into one master dataset — no unique ID, 2015–2019, 3,539 records.**

**Full Case Study & Visual Breakdown:** [Read on Notion](https://app.notion.com/p/SQL-3aaecc2fe99680e39a72eec77e955fc8?source=copy_link)

---

## Overview
This project reconciles 15 fragmented yearly source tables from a legacy registration system with no unique participant ID (`student_id`) into a single, analysis-ready master table.

* **Tech Stack:** MySQL
* **Scope:** 3,539 reconciled records · 24 branches · 5-year span (2015–2019) · 13 programs
* **Source Data:** Anonymized (all participant names replaced)

---

## Pipeline Structure

| File | Section | Description |
| :--- | :--- | :--- |
| `01_registrant_cleaning.sql` | Section 1 | Registrant data cleaning, DOB ambiguity handling, academic rollover logic, deduplication |
| `02_eligibility_cleaning.sql` | Section 2 | Eligibility status consolidation across 5 yearly batches, branch/status standardization |
| `03_graduation_cleaning.sql` | Section 3 | Graduation status consolidation, policy-based grade refactoring |
| `04_eligibility_graduation_join.sql` | Section 4 | Cross-table reconciliation (Eligibility ↔ Graduation), composite-key matching, anomaly root-cause analysis |
| `05_final_master_reconciliation.sql` | Section 5 | Multi-pass matching (Registrant ↔ Eligibility/Graduation), fan-out resolution, final master table |

---

## Key Techniques
* **Composite natural key matching** (no unique ID available)
* **Multi-pass reconciliation strategy** (high-precision match, then fallback matching)
* **Fan-out detection** and root-cause resolution
* **Bidirectional JOIN auditing** (forward + reverse)
* **Data lineage preservation** across fragmented yearly tables

---

## Key Results & Impact
* **3,539 rows** fully reconciled from 3 fragmented source tables.
* **0 confirmed intake bypass**, **0 new "ghost student" cases**.
* **674 records** classified as re-contactable "No Show" candidates.
* **215 valid re-registrations** preserved from false-duplicate misclassification.

