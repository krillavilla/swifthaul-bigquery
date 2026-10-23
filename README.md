# SwiftHaul Logistics — Analytics Warehouse in BigQuery

End-to-end BigQuery build for a fictional freight company: load and combine shipment data, model reusable metrics, optimize cost and performance, document governance, and answer leadership's questions on reliability and cost.

## Repository layout

```
swifthaul-bigquery/
├── README.md                           ← this file: setup, run order, results
├── .gitignore                          ← keeps keys and data files out of git
├── sql/
│   ├── 00_environment_setup.sh         ← bucket, upload, dataset (Cloud Shell)
│   ├── 01_load_shipments.sql           ← Task 1: dataset + LOAD DATA + validation
│   ├── 02_external_table_and_join.sql  ← Task 2: external table + enrichment join
│   ├── 03_views.sql                    ← Task 3: views + materialized view
│   ├── 04_query_optimization.sql       ← Task 4: wasteful vs optimized query
│   ├── 05_partition_and_cluster.sql    ← Task 5: partitioned/clustered copy
│   └── 07_analysis.sql                 ← Task 7: Q1–Q3c business queries
├── docs/
│   ├── 06_governance.md                ← Task 6: encryption + IAM
│   └── 07_analytical_summary.pdf       ← Task 7 analytical findings
└── screenshots/
    ├── task1_schema.png
    ├── task1_schema_infoschema.png
    ├── task2_join.png
    ├── task4_before.png
    ├── task4_after.png
    ├── task5_native.png
    ├── task5_optimized.png
    ├── task5_comparison.png
    ├── task7_q1_reliability.png
    ├── task7_q2_lanes.png
    ├── task7_q2b_cheapest.png
    └── task7_q3_cost_vs_reliability.png
```

## Run order

1. **Setup** — `sql/00_environment_setup.sh` in Cloud Shell: set project, create a `US` bucket, upload both files, **print the shipments header**.
2. **Task 1** — check the column list in `01_load_shipments.sql` against that header and the data dictionary, then run it. Confirm ~1.5M rows and that `ship_date` is `DATE` and `on_time` is `BOOL`.
3. **Task 2** — `02_…sql`: create `carrier_rates_ext`, confirm no unmatched carriers, run the join, create `v_shipments_enriched` (used by Q3).
4. **Task 3** — `03_views.sql`.
5. **Task 4** — `04_…sql`: dry-run each query, screenshot, run with caching off, record numbers.
6. **Task 5** — `05_…sql`: build the optimized table, run the identical query on both tables, screenshot both, record numbers.
7. **Task 6** — `docs/06_governance.md`.
8. **Task 7** — run `07_analysis.sql`; findings are in `docs/07_analytical_summary.pdf`.

Scripts assume project `swifthaul-bigquery` and bucket `gs://swifthaul-bigquery-data`; if you use a different bucket name, find-and-replace it in `01_` and `02_`. Turn off **More → Query settings → Use cached results** while measuring bytes.

## Results

| Task | Before | After | Reduction |
|---|---|---|---|
| 4 — `SELECT *` vs optimized (dry-run) | 189.03 MB | 81.78 MB | 56.7% |
| 5 — native vs partitioned+clustered (bytes processed) | 61.75 MB | 2.63 MB | 95.7% |

## Security note
No service-account keys, credentials or billing details are committed. Data files stay in GCS and are excluded by `.gitignore`.
