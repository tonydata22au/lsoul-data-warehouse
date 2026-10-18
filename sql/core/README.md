# sql/core/

`core_*` build/backfill scripts (`CREATE OR REPLACE TABLE … PARTITION BY … CLUSTER BY …`)
that create core tables from staging. Daily incremental loads into these tables are done by
the procedures in [`../procedures/`](../procedures/) (`sp_*_insert`), not by these files.
Rerunning a file here **rebuilds the table** in BigQuery.
