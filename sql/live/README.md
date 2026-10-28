# Live warehouse definitions

Snapshot of `marine-cycle-484213-b4`, captured **2026-10-28**. This folder is an
inventory and source backup, **not a batch deployment**. No exported SQL was executed.

| Export | Coverage |
|---|---:|
| Visible warehouse datasets | 22 |
| Hidden temporary datasets discovered (metadata unavailable) | 14 |
| Base-table DDL files | 1,047 |
| View DDL files | 236 |
| Linked billing table schema (DDL unavailable) | 1 |
| Stored procedures | 32 |
| Table functions | 58 |
| Scalar functions | 5 |
| Saved-query repositories | 103 |
| Other Dataform/pipeline repositories inventoried | 19 |
| SQLX files across HEAD/workspace versions | 458 |
| Scheduled queries with SQL and configuration | 3 |
| Other data-transfer configurations inventoried | 4 |
| Definition/configuration files in manifest | 2,275 |
| Existing routine files refreshed | 58 |

SQLX file counts include separate HEAD and workspace copies, not unique pipeline
actions. Some repositories have an empty HEAD and source only in workspaces.
Dataform discovery checked all 40 advertised locations; transfer discovery checked
all 54 advertised locations. Dataset discovery included hidden datasets and their
reported regions (`asia-southeast1` and `US`). All discovered visible warehouse
datasets are in `asia-southeast1`.

## Layout

- `bigquery/<dataset>/tables/`: current table and view DDL, one object per file.
- `bigquery/<dataset>/routines/`: current deployed function/procedure DDL.
- `bigquery/<dataset>/schemas/`: schema fallback when BigQuery provides no DDL.
- `saved_queries/<region>/<display-name>--<id>/`: saved SQL assets, with HEAD and
  accessible workspaces stored separately.
- `dataform/<region>/<name>--<id>/`: SQLX, SQL, supporting JS/JSON/YAML source and
  available workflow/release configuration. Names are URL-encoded for filesystem safety.
- `scheduled_queries/<region>/`: SQL plus schedule/destination configuration.
- [manifest.json](manifest.json): provenance, checksums, coverage, publication edits,
  transfer inventory and unresolved retrieval gaps.
- [routine_sync.json](routine_sync.json): existing routine files updated and unmatched
  legacy files retained.

## Known coverage limits

1. The 14 hidden temporary datasets reject TABLES/ROUTINES metadata access or do
   not support INFORMATION_SCHEMA. Their names and failures are recorded; no
   temporary query results were copied.
2. The linked billing dataset's single table has no DDL. Its actual schema is
   exported instead; no recreation statement was invented.
3. The externally hosted Dataform repository `opsdatalsoul/lsoul_document` cannot
   provide HEAD through Dataform's readFile API. A direct read of its GitHub main
   reference returned `Repository not found`. Its workspace was inspected, but had
   no eligible SQL/SQLX/JS/JSON/YAML source outside dependency/editor directories.
   Its Python/container source is outside this SQL-definition export.
4. Private or legacy saved queries not exposed by Dataform to this identity cannot
   be claimed as covered. Table DDL cannot recover historical transformation jobs.
5. The legacy `fn_stats_product_comments_ai_generated.sql` and
   `sp_check_partition_insert_dates.sql` have no matching deployed routine under
   their documented target; they remain in their existing locations for reference.
6. IAM grants, connections, model training history, Cloud Run container source,
   customer rows, notebooks and binary/data files are not part of this snapshot.
   Existing ingestion source remains under `src/`.

The manifest contains 31 gap records: two metadata failures per hidden dataset,
one missing billing DDL, and two observations of the external-repository limitation.
Rate-limit and exporter API-shape failures were retried and are not unresolved gaps.

Publication removed example order identifiers from SQL comments and authentication
identity configuration from workflow configs. These changes are recorded per file
with original and published hashes. Executable SQL logic was not changed. Source
formatting, including existing trailing whitespace, is otherwise preserved.

See the [sync guide](../../docs/warehouse-definition-sync.md) for refresh instructions,
source distinctions and validation. Always review dependencies and destinations
before deploying any definition.
