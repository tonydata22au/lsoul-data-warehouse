# Review report: Stable warehouse identity

Main Review passed on 2026-11-02: no unresolved correctness, security or application blockers
found in the prepared change. Two minor clarity findings were corrected. Production is unchanged;
Agent Flow controls snapshot acceptance and the subsequent Ship readiness assessment.

## Scope and review method

Reviewed the full result across `lsoul-data-warehouse` and `lsoul_dbt`: twelve reporting functions,
warehouse producer, nineteen-ID policy, dbt model/hooks/tests, provenance validation, snapshot
preservation, generated lineage and application/rollback instructions. Tests were read first.
Independent reviewers covered functions, dimension and dbt; a second-model reviewer covered
provenance. The main reviewer checked the handoff, security boundaries and mutation sensitivity.
Current-task First Principles retrieval was reused to check identity, row grain and evidence
invariants; repository code and captured runtime evidence establish the technical findings.

## Findings and resolutions

| Severity | Finding | Resolution |
| --- | --- | --- |
| Minor | The procedure comment could imply that existing unknown IDs always keep their classification, although today's source merge applies VIETNAM/P defaults. | Clarified that the source merge applies defaults and the later policy UPDATE leaves unknown IDs untouched. No executable SQL changed. |
| Minor | dbt's parity notes omitted code recalculation after a null-only label fallback and the difference in transaction boundaries. | Added both differences to `lsoul_dbt/docs/sources/pancake.md`. The procedure preserves the existing code; dbt recalculates it from the retained label. |
| Note | The provenance validator checks the format of `baseline_ddl_sha256`, not an included baseline artifact. | Retained the documented live recapture/hash comparison before application. Verify independently compared all thirteen live definitions against the captured baselines. The manifest hash alone is not deployment or baseline-integrity proof. |

The migration guide now links the completed Verify evidence. The procedure's source hash in
the pending manifest was updated for its comment-only edit. Its current SHA-256 is
`1391b349af97b29764f5bcab166f773d018b76a8dda8ce3a974f382a92b04443`.
An exact comparison after removing line comments confirms its executable SQL is unchanged
from the version used in BigQuery verification.

## Review conclusions

- **Functions:** executable diffs against the fresh live capture are limited to the intended
  warehouse operands and replacement DDL. Header IDs, online OR grouping, labels, signatures,
  mode branches, joins, dates and financial calculations are preserved. Inspection of all 41
  table functions in the captured 47-routine inventory found no missed target.
- **Dimension:** deterministic newest nonblank names, one row per ID, invalid-target guards,
  absent-source corrections and existing activity semantics match the specification. The
  procedure avoids delete/insert gaps; the seven known live classification mismatches remain
  unapplied until production application.
- **dbt:** policy rows match, hooks resolve to dbt-only datasets and retain the existing watermark
  ordering, incremental/full-refresh behavior is documented, and generated lineage distinguishes
  observed live definitions from pending sources. No new runtime cross-repository dependency.
- **Provenance and security:** explicit source/snapshot hashes and path boundaries remain enforced;
  amendments preserve original snapshot-manifest history. Published example order literals remain
  redacted. No credentials, new dependencies, production writes or target repointing were added.
- **Performance and maintainability:** reporting changes preserve query shape; policy joins are
  bounded to nineteen rows. The dimension retains its source window and existing inventory-history
  activity scan. Policy duplication across deployment units is checked by parity regressions.

## Validation during Review

An isolated copy changed the VN online predicate from OR to AND. The seven-test function suite
passed before mutation, failed on the mutation (including the source-or-identity behavior case),
then passed after restoring the copied source. Workspace source bytes were never changed by this
experiment. The expected failing run and its restored rerun are recorded separately.

After the comment/documentation corrections, all checks passed:

- Warehouse static validator, full unit suite (42 tests, one existing skip), provenance validator
  and whitespace check.
- dbt parse, project validator, renderer (92 statements / 61 models), full unit suite (37 tests),
  SQLFluff, inventory check and task-source whitespace check.
- Original dbt log preservation: SHA-256 remains
  `c1df870ff89570a65a54d94a2cf63d6aff246161d769cdbbe4a49686a2bf604b`.

The pre-existing log whitespace is preserved and excluded from task-source whitespace checks.
Lineage inputs did not change during Review; the passing Verify-stage lineage tests/build remain
applicable. Review made no cloud calls. Existing BigQuery compilation, aggregate and temporary
procedure results remain applicable because executable SQL did not change.

Exact command results and mutation logs are in
[warehouse-review](/Users/tony.pham/.bb/thread-storage/thr_qjwbpax4cj/warehouse-review).
See [Verify report](verify-report.md) for the cloud checks and their limits.

## Remaining application boundary

The changes are prepared and tested, not deployed. Production routine permissions, scheduler
execution, persistent-table concurrency and dbt adapter execution were not tested. Temporary
guard tests use an outer rollback and do not inject a failure after a successful write. These
limits do not invalidate the demonstrated identity correction and remain explicit for readiness.

Before application, follow [the migration guide](../docs/warehouse-identity.md): recapture live
definitions, reconcile concurrent changes, back up the dimension, preflight keys and policy,
apply in the documented order, and verify readback. Routine rollback alone cannot restore
dimension data; restoring the captured VN store v2 routine also restores its known filter bug.
