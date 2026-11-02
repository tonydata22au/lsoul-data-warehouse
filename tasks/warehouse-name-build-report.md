# Canonical warehouse names: Build report

Status: implemented locally on 2026-11-02. Production is unchanged. Agent Flow Verify and
Review remain; the earlier predicate-only Ship verdict does not certify this extension.

## Delivered

- Updated 37 table functions: 15 Pancake sales, 14 overseas sales, eight inventory/report consumers.
  Five wrappers inherit names; seven more aggregate consumers remain in the 49-function regression scope.
- Preserved the earlier twelve ID-filter repairs. Actual warehouse names resolve through
  `core_pancake.core_warehouse`, matching returned IDs. Header filters keep their original identity.
- Overseas constant-ID lookups preserve aggregation; other lookups use distinct column aliases to
  avoid ambiguous warehouse fields. Unknown IDs retain rows with NULL names. Aggregate blanks remain.
- Preserved inventory source partitions, cutovers and stock calculations. Assortment grouping now
  includes warehouse ID to keep two warehouses distinct when their current names coincide.
- Preserved the richer preexisting inventory-summary-v2 draft byte-for-byte in
  [the archive](../sql/archive/zarchived-fn_product_inventory_summary_v2-pre-canonical-20261102.sql).
  The maintained source uses the captured live interface; the archive has a validated provenance hash.
- Extended strict pending-source provenance to all direct targets, with exact live baseline hashes.
  Captured rollback DDLs remain private in thread storage `warehouse-name-build/rollback/`.
  Immutable observed snapshots and the previously prepared producer/dbt work remain intact.

## Build evidence

Final repository validation passed: `validate_repo.py`, `validate_sql_sources.py`, and
`git diff --check`. `python3 -m unittest discover -s tests` passed 107 tests with one existing
skip. The known Thai TikTok service-wiring warning remains unrelated to these SQL changes.

TDD first reproduced old-name behavior, missing name-source coverage and the missing archive
integrity guard. Family tests then passed after each slice. Tests execute extracted SQL using
SQLite and compare full bodies after undoing only exact reviewed name changes. They cover renames,
name reuse, null/unknown IDs, item/header disagreements, fixed labels, row/quantity preservation,
summary blanks, source-system stock partitions and persisted stale names. Mutation checks exercise
wrong IDs/joins/dimensions, stale literal names and changed financial multipliers.

GoogleSQL dry runs compiled all 37 proposed SELECT bodies, using representative warehouse-grain
parameters. These are dry runs only: no function DDL was executed and no production data changed.
The first input-hash reconciliation detected subsequent whitespace cleanup in three inventory
files; those three final sources were recompiled and the complete hash set reconciled again.
Detailed outputs are in thread storage `warehouse-name-build/compile-results-all.json`.

## Verify-stage work still required

- Compile the full proposed dependency graph and verify output schemas/modes against live baselines.
  Build dry runs resolve dependency calls to currently deployed functions; they do not prove the
  combined undeployed graph or unchanged output schemas across every mode.
- Exercise warehouse-only or synthetic/aggregate BigQuery comparisons where useful, including
  scalar duplicate rejection and duplicate-dimension preflight. SQLite cannot prove BigQuery scalar
  duplicate behavior. Joins require unique dimension IDs; the previously prepared producer is pending.
- Check restored-warehouse membership separately from unchanged financial/stock calculations; the
  broken original VN-store-v2 predicate is not an equality oracle. Check inventory date cutovers.
- Check the 49-function dependency scope and caller access to the added dimension references.
- Recapture live DDL and reconcile concurrent changes before any later application. Roll back exact
  captured routine definitions; if the separate dimension migration is applied, retain its table backup.

No deployment, report refresh, ingestion, dbt execution, commit, branch switch or push occurred.

Canonical Holistics instructions were freshly read for this stage. The same-task First Principles
retrieval remains applicable to separating IDs, canonical names and source-stock keys. Bound
incremental-implementation and test-driven-development skills guided family slices and RED/GREEN
checks; the repository's validation skill guided final offline checks. Three workers owned separate
SQL families; the parent integrated provenance, compilation, documentation and the full suite.
