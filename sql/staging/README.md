# sql/staging/

`stg_*` scripts that build typed staging tables from raw ingestion tables
(`CREATE OR REPLACE TABLE … PARTITION BY DATE(proc_date) AS SELECT … FROM raw…`).
`proc_date` is derived from the raw table's `_PARTITIONTIME`.

- `stg_pancake_order.sql` and `stg_pancake_orders_returned.sql` are Dataform SQLX
  (`config { … }`, `${ref(...)}`), not plain BigQuery SQL.
- Several files filter on hard-coded partition dates; review them before rerunning.
- Staging does not deduplicate; see [`../README.md`](../README.md#behaviors-to-know-before-editing).
