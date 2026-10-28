# sql/

All BigQuery SQL for the LSOUL warehouse. Everything targets the GCP project
`marine-cycle-484213-b4` (location `asia-southeast1`). Nothing in this repo runs these
files automatically: they are deployed by pasting/running them in BigQuery (console,
`bq query`, or Dataform for the two SQLX-style staging files). **Running any file here is a
BigQuery write** (`CREATE OR REPLACE TABLE`, `CREATE OR REPLACE PROCEDURE/FUNCTION`,
`DELETE`/`INSERT`). Read the file first; never run one just to "test" it.

| Folder | Contents | Object types |
|---|---|---|
| [`staging/`](staging/) | `stg_*`: typed/cleaned copies of raw tables | `CREATE OR REPLACE TABLE … PARTITION BY DATE(proc_date)`; `stg_pancake_order.sql` and `stg_pancake_orders_returned.sql` are Dataform SQLX (`config {…}`, `${ref()}`) |
| [`core/`](core/) | `core_*`: build/backfill scripts for core tables | `CREATE OR REPLACE TABLE … PARTITION BY … CLUSTER BY …` (one `INSERT`) |
| [`procedures/`](procedures/) | `sp_*`: incremental staging → core loads, logging, dashboard jobs | `CREATE OR REPLACE PROCEDURE` |
| [`functions/`](functions/) | `fn_*` reporting table functions (`reportdb`), `sys-*` shared scalar UDFs | `CREATE OR REPLACE TABLE FUNCTION` / `FUNCTION` |
| [`marts/`](marts/), [`checks/`](checks/) | Placeholders (empty today) | — |
| [`ad_hoc/`](ad_hoc/) | `q-*` one-off analysis and monitoring queries | Mostly `SELECT`; `q-ai_performance_snapshot.sql` also creates views |
| [`working_files/`](working_files/) | Numbered deployment set for the AI performance dashboard (`01`–`08`) plus scratch (`00-*`) | Mixed DDL/DML; see file headers for run order |
| [`archive/`](archive/) | `zarchived-*` superseded versions kept for reference | Do not deploy |

## Live definitions and pipeline source

The [live snapshot](live/README.md) records the current accessible deployed objects,
saved queries, scheduled queries and Dataform source. See the
[sync guide](../docs/warehouse-definition-sync.md) for scope, provenance and refresh steps.
The snapshot separates schema DDL from transformations; it is not a batch deployment.
Matching function/procedure files here are refreshed from deployed routines. Historical
CTAS/backfill and working files are retained and may differ from the live source.

## Data flow

```text
Python loads (src/)            raw_<source> / <source>.raw_*   append-only, ingestion-time partitioned
  → staging/ (CTAS/Dataform)   stg_<source> / <source>.stg_*
  → procedures/ sp_*_insert    core_<source> / <source>.core_*  DELETE by id + INSERT latest, logs to sysdb
  → functions/ fn_*            reportdb table functions          computed at query time
  → working_files/ dash_*      reportdb dashboard tables/views
```

Dataset naming: Pancake, TikTok and Meta use one dataset per layer (`raw_pancake`,
`stg_pancake`, `core_pancake`, …); Dianplus, Jushuitan, Surfosm and Magento keep all layers
in one dataset per source (`dianplus.raw_dianplus_order`, `dianplus.stg_…`, `dianplus.core_…`).
Shared datasets: `reportdb` (functions, dashboards), `sysdb` (load logging).

Example chain: `raw_pancake.raw_order` → `stg_pancake.stg_order` → `sp_core_order_insert` →
`core_pancake.core_order` → `reportdb.fn_sale_ecom_vn_v2` → `reportdb.fn_order_master`.

## Behaviors to know before editing

- Raw tables are append-only and overlapping date windows are re-fetched, so **raw and
  staging contain duplicates**. Deduplication happens in core (`DELETE` by id + `INSERT`,
  `GROUP BY` + `MAX(updated_at)`, or `SELECT DISTINCT`).
- `sp_*_insert` procedures only load when the newest staging partition is today's date in
  `Asia/Ho_Chi_Minh`; otherwise they only write a log row via `sysdb.sp_data_insert_log*`.
- Some staging files hard-code partition dates (e.g. `= "2026-06-01"`); check before rerunning.
- Several objects are referenced but not defined here (e.g. `sysdb.sp_data_insert_log_V3`,
  `fn_sale_store_thai_v2`, `core_meta.*`). The live BigQuery definition is the source of truth.
- File names don't always match the object they create (e.g. `core_tiktok_ad.sql` creates
  `core_tiktok.core_thai_ads`). Search for the object name, not just the file name.

## Conventions for new SQL

- One object per file, named after the object: `stg_<source>_<entity>.sql`,
  `core_<source>_<entity>.sql`, `sp_<source>_core_<entity>_insert.sql`, `fn_<purpose>.sql`.
- Always fully qualify tables with project and dataset (backticks).
- Use `CREATE OR REPLACE` only where a full rebuild is intended; document partition filters.
- Move superseded files to `archive/` with the `zarchived-` prefix instead of deleting them.
