---
name: bigquery-schema-and-loads
description: Maintain LSOUL BigQuery raw table schemas and load behavior, and the staging/core SQL that depends on them. Covers COLUMN_RENAME_MAP, STRING-typed append loads with field addition, destructive src/schema scripts, ingestion-time partitioning, staging CTAS, sp_*_insert delete-and-insert procedures and deduplication. Use when adding/renaming columns, changing tables, partitions, write dispositions or SQL layers.
---

# Maintain BigQuery schemas and load behavior

## Purpose

Change what lands in BigQuery, or how, without breaking downstream SQL or losing data.

## Prerequisites

- Read [sql/README.md](../../../sql/README.md) and the pipeline's row in [docs/pipelines.md](../../../docs/pipelines.md).
- Know which objects read the table: `git grep -n "<table_name>" sql/ notebooks/`.
- **Authorization** before running any DDL/DML, schema script, or procedure in BigQuery.

## How loads work today (facts to preserve)

- Raw loads: `load_table_from_dataframe`, `WRITE_APPEND`, `autodetect=False`,
  `ALLOW_FIELD_ADDITION` and `ALLOW_FIELD_RELAXATION`; every column cast to STRING (`nan`/`None` → `''`).
  New columns appear automatically on the next load; renamed columns become *new* columns.
- The raw column set is the values of the script's `COLUMN_RENAME_MAP` (commented-out entries are not loaded).
- Raw tables are partitioned by ingestion day (`_PARTITIONTIME`), mostly with `require_partition_filter`.
- Staging (`sql/staging/`) is rebuilt with `CREATE OR REPLACE TABLE … PARTITION BY DATE(proc_date)`;
  `proc_date` comes from `_PARTITIONTIME`. Two files are Dataform SQLX.
- Core loads (`sql/procedures/sp_*_insert.sql`) delete the IDs present in today's staging partition
  and reinsert the latest version; they log to `sysdb`.
- `src/schema/` scripts **delete and recreate** the table if it exists (data loss), then optionally
  load a CSV with `WRITE_TRUNCATE`.

## Steps: add or change a column end to end

1. Edit `COLUMN_RENAME_MAP` (and any type/clean helper lists such as date columns) in the Cloud Run
   script; mirror the change in `local_run/`/`csv_export/` variants if they load the same table.
2. Update the matching `src/schema/` script's field list so a future rebuild matches (don't run it).
3. Update the staging SQL to select/cast the new column; update core build/procedure SQL if needed.
   Keep fully qualified names and the existing partition logic.
4. For a **rename**, keep the old column populated or add a staging `COALESCE(new, old)`; existing
   raw partitions keep the old name.
5. Update `docs/pipelines.md` if the destination or load behavior changed.
6. Validate offline:
   ```bash
   python3 scripts/validate_repo.py
   python3 -m unittest discover -s tests
   .venv/bin/python scripts/validate_repo.py --imports
   ```
7. List the BigQuery actions that need authorization, in order (e.g. deploy pipeline → wait for a
   load → `CREATE OR REPLACE` staging → `CREATE OR REPLACE PROCEDURE` core).

## Expected result

Code, schema script and SQL agree on column names; nothing was executed in BigQuery; the hand-back
lists the deployment steps and who must run them.

## Operational limits

- Never run `src/schema/` scripts against existing tables; never `DROP`/`TRUNCATE`/`DELETE` raw data.
- Don't change `WRITE_APPEND` to `WRITE_TRUNCATE`, partitioning, or destination names without agreement.
  These are interfaces for downstream SQL and dashboards.
- `bq query --dry_run` validates SQL but still contacts BigQuery; it needs authorization.
- Don't copy query results containing personal data into the repo.

## Proposed (not implemented)

- Versioned, non-destructive schema migrations (`ALTER TABLE ADD COLUMN`) instead of drop/recreate scripts.
- Typed raw schemas with contracts and data-quality checks in `sql/checks/`.
