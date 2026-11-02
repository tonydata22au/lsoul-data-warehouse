# Verify report: Stable warehouse identity

Verification passed 2026-11-02 on the existing `main` branches in `lsoul-data-warehouse` and `lsoul_dbt`.
Production routines and tables remain unchanged. BigQuery validation used read-only metadata,
bounded aggregate SELECTs and synthetic temporary tables; no persistent DDL/DML or dbt run occurred.
Independent Review and Ship readiness assessment remain.

## Offline checks

All thirteen commands passed, plus the original dbt log preservation assertion:

| Repository | Checks |
| --- | --- |
| Warehouse | Repository validator; 42 unit tests (one existing skip); source-provenance validator; diff whitespace check |
| dbt | Parse; project validation; render 92 statements / 61 models; 37 unit tests; SQLFluff; inventory check; task-source diff check |
| Lineage | 15 tests; production frontend build |

Command arguments, exit codes and outputs are recorded in
[/Users/tony.pham/.bb/thread-storage/thr_qjwbpax4cj/verify-offline/results.json](/Users/tony.pham/.bb/thread-storage/thr_qjwbpax4cj/verify-offline/results.json).
Existing Thai Ads, dbt dependency and lineage warnings remain documented in the build report.
The pre-existing whitespace in user-modified `lsoul_dbt/logs/dbt.log` was excluded from the task-source
diff check; its SHA-256 remains `c1df870ff89570a65a54d94a2cf63d6aff246161d769cdbbe4a49686a2bf604b`.
The earlier full-diff failure is not represented as repaired.

## BigQuery compilation and live preflight

- Forty function-body dry runs passed: baseline and proposed definitions for all twelve functions,
  with modes 0/1/3 for each v2 function. All twenty proposed output schemas match their baselines.
- The dimension source SELECT compiled using the real source schema and accent UDF, preserving
  all eight output columns. A bounded aggregate found ten rows, ten unique IDs, no blank IDs,
  no null names and no unknown policy IDs in the selected source partition.
- Fresh routine metadata matched all thirteen captured build baselines; no concurrent edits found.
- The live dimension preflight found no duplicate, blank or unknown IDs. It reported seven
  country/type mismatches, exactly the existing drift the proposed ID policy is intended to repair.
  These mismatches remain in production until application.

Raw compilation, schema and preflight evidence is in
[warehouse-verify](/Users/tony.pham/.bb/thread-storage/thr_qjwbpax4cj/warehouse-verify).

## Representative reporting aggregates

Compared the captured live and proposed v2 bodies for all four families and modes 0/1/3.
Each query returned only period, output-row count, units and revenue, for 2026-10-18–23 and
2026-10-26–11-01. All twenty-four executions passed under a 1 GB per-query ceiling.

| Family | Earlier period: baseline → proposed units | Later period: baseline → proposed units |
| --- | --- | --- |
| VN ecommerce | 95 → 346 | 0 → 333 |
| VN online | 207 → 207 | 188 → 188 |
| VN stores | 0 → 462 | 0 → 405 |
| Thai stores | 69 → 69 | 0 → 90 |

Units agree across all three modes. VN online rows/revenue match in both periods, and Thai
rows/revenue match in the earlier period. VN store recovery corrects the current live function's
UUID comparison against the name column. Four additional aggregate attribution queries confirmed
that every ecommerce recovery has the intended ID and current order-header name
`VN – E-commerce Stock`. The old-name subgroup exactly matches the baseline; no ambiguous mapping
or old-name orders outside the intended ID were found. This also explains recovery in older orders.
All row, unit and revenue deltas reconcile exactly. Full mode-level results are in
[function-aggregate-comparisons-final.json](/Users/tony.pham/.bb/thread-storage/thr_qjwbpax4cj/warehouse-verify/function-aggregate-comparisons-final.json).

Six initial Thai aggregate-wrapper dry runs failed because the verification wrapper referenced
`revenue` instead of the existing `revenue_th` output. Only the private wrapper changed; all six
reruns passed. Four initial attribution dry runs likewise used `order_date` on `core_order`, whose
field is `inserted_at`; those private wrappers were corrected and all four reruns passed. These
were test-wrapper errors, not implementation edits. All ten original failures and linked reruns
are retained in [the check manifest](/Users/tony.pham/.bb/thread-storage/thr_qjwbpax4cj/warehouse-verify/aggregate-check-manifest.json).
The final aggregate reconciliation check passed. The evidence-index audit initially expected
`kind=execute` instead of the manifest's `kind=execution`; correcting that audit made it pass,
with the failure and rerun linked separately. No unresolved check failures remain.

## Procedure execution on synthetic temporary tables

The actual proposed procedure body was executed as anonymous BigQuery blocks after replacing its
three persistent table references with temporary fixtures and its accent UDF with a temporary
test function. Static checks found zero persistent resource references in those scripts.

- Five refresh executions passed 24 assertions: duplicate/mixed/null labels, deterministic label
  selection, current/stale/empty source, absent-source classification, inactivity and reactivation,
  unknown-ID default, and repeat refreshes.
- Duplicate, null and blank target IDs each raised the intended guard. Six post-error assertions
  confirmed the expected error was caught and rollback preserved all target fields.
- Both jobs completed successfully with a 1 GiB ceiling and `datacloud:codex` attribution. The
  proposed procedure source remained byte-for-byte unchanged.

Commands, jobs, fixture SQL and outputs are in
[warehouse-id-verify-procedure](/Users/tony.pham/.bb/thread-storage/thr_qjwbpax4cj/warehouse-id-verify-procedure).
BigQuery dry runs alone do not validate this control flow: they stop at conditional/DDL boundaries.
See [Google's dry-run behavior](https://docs.cloud.google.com/bigquery/docs/multi-statement-queries)
and [transaction documentation](https://docs.cloud.google.com/bigquery/docs/transactions).

## Scope and limitations for Review

- Live aggregate execution covered v2 bodies; base/product bodies were compiled and exercised by
  offline identity regressions. Date coverage is representative, not exhaustive historical parity.
- The procedure test validates its body and temporary-table transaction behavior. It does not
  validate deployed routine permissions, the real scheduler or persistent-table concurrency. The
  guard-error tests do not inject a failure after a successful write.
- dbt was parsed, rendered, linted and tested offline; its adapter merge/post-hooks were not run
  in BigQuery. Existing source-window and rebuild-date differences remain intentional.
- On null-only input, the procedure preserves existing name and code; dbt preserves the name
  and recalculates its code. They agree when the stored code already matches the accent UDF.
  dbt's tests/merge/hooks also do not provide the procedure's same pre-write guard/transaction boundary.
- Unknown new IDs retain the documented VIETNAM/P compatibility default and require policy review.
- Production application remains outstanding under this Agent Flow's no-deployment boundary.
  Use [the migration and rollback guide](../docs/warehouse-identity.md) after the later review gates.
