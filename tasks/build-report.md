# Build report: Stable warehouse identity

Built 2026-11-02 on the existing `main` branches. No commits, deployments, production DDL/DML,
pipeline runs or dbt warehouse jobs were performed. Verify and independent Review remain.

## Implementation

- Twelve reporting functions now use order-header warehouse IDs for membership and store channel
  classification. Existing online OR logic, interfaces, labels, financial/date expressions remain.
  Nine previously missing sources are in `sql/functions/warehouse_identity/`.
- The warehouse producer uses a transaction, rejects invalid target keys, chooses deterministic
  latest nonblank labels and MERGEs on ID. Known-ID classification corrections include rows absent
  from today's load; activity and source-day semantics remain. No logging calls were restored.
- `sql/config/warehouse_policy.json` records nineteen verified IDs and compatibility choices.
  A SELECT-only preflight checks keys, coverage and classifications; it has not been run.
- Sibling dbt uses a local policy macro and correction post-hook, preserving dbt-only destinations,
  eight-column schema and source windows. Offline regressions execute rendered SQL; a separate
  dbt data test reports unknown policy IDs when later authorized to run.
- Updated dbt documentation, inventory and generated lineage. Lineage continues to distinguish
  observed live sources from pending changes. Source hashes and provenance are explicit.

## Existing validation defects addressed

The three missing monitoring connector files were regenerated with the existing offline generator.
No monitoring logic changed. The prior raw-product snapshot edit and `fn_dim_sku` source divergence
are explicitly recorded with exact hashes and original commit provenance, preserving all existing
SQL and original snapshot-manifest bytes. Snapshot validation still rejects undeclared changes.
Finder `.DS_Store` metadata is ignored without deleting it; all SQL/configuration files are checked.

## Checks executed

| Check | Result |
| --- | --- |
| Fresh read-only live routine capture | 47 bodies; unchanged from Plan |
| Function regression RED → GREEN | 72 initial failing subtests; final seven tests pass across twelve functions |
| Dimension regression RED → GREEN | Initial ten failures; final twelve tests pass, including key preconditions and repeated calls |
| Provenance regression RED → GREEN | Missing validator reproduced; final seven tests pass, rejecting mutations/invalid records |
| Warehouse `validate_repo.py` | Pass; existing Thai Ads service warning |
| Warehouse full unittest suite | 42 tests, pass; one existing skip |
| Warehouse `validate_sql_sources.py` | Pass; thirteen pending objects plus pre-existing source divergence |
| Warehouse `git diff --check` | Pass |
| Existing snapshot/source preservation check | Pass; affected pre-existing SQL and original manifest equal HEAD bytes |
| dbt regression RED → GREEN | Initial behavior/macro failures; seven tests pass after implementation |
| dbt parse | Pass |
| dbt `check_project.py` | Pass; existing documented core dependency warning |
| dbt `render_models.py` | Pass: 92 statements / 61 models |
| dbt offline unit suite | Pass: 37 tests |
| SQLFluff | Initial indentation failure fixed; rerun passes |
| Inventory generation/check | Pass |
| Lineage tests/generation/build | Pass: 15 tests; four existing lineage warnings |
| dbt full `git diff --check` | Exit 2: pre-existing whitespace in user-modified `logs/dbt.log:631` |
| dbt task-source-only diff check | Pass; original log remains byte-for-byte unchanged |

Preserved dbt log SHA-256: `c1df870ff89570a65a54d94a2cf63d6aff246161d769cdbbe4a49686a2bf604b`.
This remaining full-diff failure is recorded honestly; no log cleanup was made to obtain a pass.

## Limits and handoff

Offline fixtures execute SQL predicates, source selection and classifications via SQLite adaptations;
they do not execute full BigQuery functions or validate transaction semantics. The v2 mode branches
and all unrelated executable SQL are compared for preservation, not executed on production orders.
BigQuery compilation, representative aggregate checks and independent review belong to subsequent
stages. The default country/type for unknown IDs remains VIETNAM/P; review coverage warnings.

Use [migration instructions](../docs/warehouse-identity.md) for prepared preflight, application and
rollback sequence. Application is outstanding because this Agent Flow never deploys. The two
repositories retain all original changes and branches; no secrets or customer records were read.
