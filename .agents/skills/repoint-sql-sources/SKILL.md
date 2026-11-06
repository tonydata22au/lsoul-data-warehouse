---
name: repoint-sql-sources
description: Repoint LSOUL BigQuery functions, procedures and table scripts from one set of tables/datasets to another (for example dianplus.core_dianplus_* to core.core_dianplus__*), list what changed, wait for review, baseline the old results, deploy to BigQuery, then verify the new results equal the old. Use when asked to switch objects to read from different tables or datasets.
---

# Repoint SQL objects to different source tables

## Purpose

Swap table references across `sql/` objects safely: edit files, report, get review, deploy, test.
Never skip the review gate: deployment replaces live objects.

## Steps

1. **Pin the mapping.** Get old to new table names from the user. Confirm the new tables exist
   with read-only metadata (`bq ls <dataset>` or the BigQuery MCP `list_table_ids`). Ignore
   `__dbt_tmp*` leftovers. Names may differ by more than the dataset (single vs double underscore).
2. **Find users of the old tables.** Grep `sql/` excluding `sql/live/` and `sql/archive/`
   (use `grep -rn`, quote globs for zsh). Classify each hit:
   - *Readers* (functions, procedures, views, working_files): repoint.
   - *Writers* (procedures that `DELETE`/`INSERT` into the old table, core build scripts):
     do **not** repoint silently; changing a write target changes pipeline output. Flag and ask.
   - *Monitoring / INFORMATION_SCHEMA / comments*: leave, mention.
   - Build scripts that read staging (`stg_*`) are not core readers: leave.
3. **Edit only the one editable file** per object (`sql/<layer>/<dataset>.<object>.sql`), never
   `sql/live/`. Use a precise `sed`/Edit on the fully qualified name
   (`` `marine-cycle-484213-b4.<dataset>.<table>` ``) so only table names change.
4. **Show the diff and the report**: per object, old table to new table; what was left alone and
   why; note that columns/types were not compared unless you did (offer to compare with
   `get_table_info`). Then **stop and wait for review.**
5. **Baseline the OLD objects first (before any deploy).** While the live objects still use the
   old tables, run each one and record its result. Do not skip this: once the new definition is
   deployed the old output is gone. For each function/procedure output, choose argument sets
   that cover the data (read the signature; try every meaning of type/flag args, a recent window
   and a wider one) and record, per call: `COUNT(*)`, `SUM` of every numeric column, `COUNT(DISTINCT)`
   of key columns, and an order-independent content hash, for example
   `BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t)))` over `FROM fn(args) t`. Aggregates only; never
   print rows with personal data. Save the baseline numbers in the conversation (or, if the user
   agrees, in a scratch table so the full row-level `EXCEPT DISTINCT` is possible in step 7).
   If the old and new source tables are populated at different times they may legitimately
   differ; check the sources' freshness (`MAX` of the date/proc column) and report it.
6. **Deploy only after the user says so** (per-action authorization, see AGENTS.md Boundaries):
   `bq query --project_id=marine-cycle-484213-b4 --location=asia-southeast1 --use_legacy_sql=false < sql/<layer>/<file>.sql`
   one file at a time; each should print `Replaced ...`. Table functions are validated at
   creation, so bad columns fail here. Core `CREATE OR REPLACE TABLE` scripts rebuild data:
   confirm that explicitly before running those.
7. **Compare NEW vs OLD and require equality.** Re-run the exact same calls and metrics from
   step 5 against the deployed new objects. Every metric must match exactly (row count, sums,
   distinct counts, hash); with a baseline table also run `EXCEPT DISTINCT` both ways and expect
   zero rows. Report a table of call, metric, old, new, match. If anything differs: do not call
   it done. Find the cause (column renames, type changes, dedup differences, different data
   freshness), show the user, and either fix the SQL or ask. If the user wants to proceed
   despite differences, record the accepted differences explicitly. If the new result is wrong,
   offer to redeploy the previous definition from `git` (`git show HEAD:<file>`).
   Say what args you used and which were guesses.
8. **Follow-ups to offer**: refresh `sql/live/` (docs/warehouse-definition-sync.md);
   `python3 scripts/sql_index.py --drift` shows undeployed edits; run `validate-changes`.

## Reporting

List objects updated with old to new table, objects deliberately skipped with reasons, deploy
status per object, and the old-vs-new comparison table (match / mismatch per call). State plainly what was not verified.
