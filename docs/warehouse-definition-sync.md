# Warehouse definition sync

The live definition snapshot is in [sql/live](../sql/live/README.md). It is an inventory
and source backup, not a deployment bundle. Do not run the directory as a batch.

## Scope and provenance

The export reads metadata for `marine-cycle-484213-b4`, using the current gcloud
identity. It does not read table rows, execute source SQL, trigger pipelines, or
change cloud resources. INFORMATION_SCHEMA reads create billed query jobs; API
listing and source downloads are read-only.

- BigQuery: dataset-specific `INFORMATION_SCHEMA.TABLES` and `ROUTINES`, including
  exact available DDL for base tables, views, scalar/table functions, and procedures.
- Dataform: repositories in every location advertised by the API, following pagination;
  committed HEAD and each accessible workspace are separate directories. Workspace
  drafts are not proof of deployment. SQL, SQLX, JavaScript, JSON and YAML are included;
  dependency/editor directories (`node_modules`, `.venv`, `.vscode`), credential-like paths, notebooks, and data files are excluded.
- BigQuery saved queries: SQL assets exposed as Dataform repositories. Legacy/private
  queries not exposed to this identity are not guaranteed to be covered.
- BigQuery Data Transfer Service: configurations in every advertised location;
  SQL and schedule metadata for scheduled queries. Other transfer types are inventoried
  without source connection parameters or authentication configuration.

A table's DDL describes its structure. It cannot recover the historical INSERT,
MERGE, or CTAS that populated it. Those definitions are retained where available
in routines, saved queries, or Dataform sources. Cloud Run ingestion source remains
under `src/`; deployed container images were not reverse-engineered.

`manifest.json` records resource paths, file hashes, discovery coverage and explicit
failures. The capture spans a time interval, not an atomic project snapshot. A complete
read of accessible definitions does not prove that this identity can list all private
resources. Source URLs and identities are not access credentials, but end-user auth
configuration and example order identifiers in comments are removed for publication.
Files with publication edits record the original hash and applied changes.

## Existing SQL

Matching files in `sql/functions/` and `sql/procedures/` are refreshed from deployed
routine bodies while retaining their `CREATE OR REPLACE` deployment behavior. The
existing four-function money helper bundle remains a bundle; the snapshot also has
one file per function. `routine_sync.json` records updated files and unmatched legacy
files. Older CTAS/backfill, ad hoc and working files are retained because replacing
transformations with schema-only DDL would destroy their purpose. Consult the live
snapshot and pipeline source before using those historical files.

## Repeat the export

Authenticate the CLI as an account with access to the intended project, then export
into a new temporary directory:

```bash
python3 scripts/export_warehouse_definitions.py \
  --project marine-cycle-484213-b4 \
  --output /tmp/lsoul-definitions-new
```

The destination must not already exist. The exporter intentionally does not delete
or overwrite previous snapshots, execute exported SQL, commit, or push. It requires
`gcloud` and `bq` on PATH and a Python environment with a working system CA store.
If Python's CA store is unavailable, set `SSL_CERT_FILE` to your installed trusted
CA bundle; never disable TLS verification. The script reads no repository `.env`
or service-account key files. Dataform requests are throttled with bounded retries.

Review the manifest and resolve retriable failures first. Review every exported
source for embedded secrets and customer literals before copying it into this public
repository; the exporter produces unreviewed source, not a guaranteed safe archive.
Preserve unmatched existing files and distinguish deployed routines from drafts.
Then run:

```bash
python3 scripts/validate_repo.py
python3 -m unittest discover -s tests
```

Validate file hashes and counts against the manifest. Do not run CREATE, DELETE,
INSERT, CALL, or Dataform invocations to validate an export. Push only when requested.

## API references

- [BigQuery TABLES metadata](https://cloud.google.com/bigquery/docs/information-schema-tables)
- [BigQuery ROUTINES metadata](https://cloud.google.com/bigquery/docs/information-schema-routines)
- [Dataform repository file reads](https://cloud.google.com/dataform/reference/rest/v1/projects.locations.repositories/readFile)
- [Dataform workspace file reads](https://cloud.google.com/dataform/reference/rest/v1/projects.locations.repositories.workspaces/readFile)
- [Dataform quotas](https://cloud.google.com/dataform/docs/quotas)
