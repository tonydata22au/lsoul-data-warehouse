# Ship readiness: Stable warehouse identity

Verdict: **GO for controlled application of the prepared source changes.** No unresolved source
blockers were found. Production application remains outstanding: this Agent Flow assesses
readiness only and never deploys. No production routines or dimension rows were changed, and
neither repository was committed or pushed.

## Delivered result

- Twelve maintained reporting functions use verified order-header warehouse IDs for selection
  and related store labels, preserving interfaces, Boolean logic and calculations.
- The warehouse producer maintains one deterministic row per ID with a transactional merge,
  invalid-key guards, latest useful labels and the nineteen-ID classification policy.
- The sibling BB project `proj_3598auxu2c` (`lsoul_dbt`) has the matching model, policy, tests,
  parity notes and generated lineage, retaining dbt-only destinations.
- [SPEC.md](../SPEC.md) contains the optimised prompt. The
  [migration guide](../docs/warehouse-identity.md) identifies exact application sources and order.

## Readiness evidence

The [Verify report](verify-report.md) records forty successful function-body compilation checks,
twenty matching proposed schemas, twenty-four v2 aggregate executions and four attribution
queries. Recovered sales reconcile to the intended IDs. Temporary BigQuery tests passed five
procedure executions with 24 assertions plus target-key guard/rollback cases.

The [Review report](review-report.md) records independent function, dimension, dbt and second-model
provenance reviews with no blockers. Two minor clarity findings were fixed. Warehouse and dbt
offline checks passed afterward; the intentional OR-to-AND mutation was caught and its restoration
passed. Review's procedure change was comment-only, preserving the executable SQL already tested.

Ship locally confirmed that all thirteen current pending source hashes match their manifest,
every retained exact rollback DDL matches its captured baseline hash, prior check records pass,
both branches remain `main`, and the original dbt log remains unchanged. An independent rollback
audit reached the same readiness conclusion. Ship made no cloud calls.

Readiness-check artifact:
[readiness-check.json](/Users/tony.pham/.bb/thread-storage/thr_qjwbpax4cj/warehouse-ship/readiness-check.json).
The original dbt log whitespace and previously documented warnings remain preserved; they do not
affect these source changes. No dependency, endpoint or UI changes require unrelated launch checks.

## Required application-time steps

These operational prerequisites have not been executed and must precede production writes:

1. Recapture live definitions and compare with the reviewed baseline. Reconcile concurrent edits.
2. Create and verify a uniquely named backup of `core_pancake.core_warehouse`. The retained routine
   DDL is available; a production table backup has **not** been created by this flow.
3. Coordinate overlapping warehouse refreshes during application and possible rollback so legitimate
   updates after the backup are not overwritten. Confirm the executing identity and intended region.
4. Run the prepared dimension preflight. Duplicate/blank keys or newly unreviewed warehouse IDs
   block application. The seven already observed classification mismatches are expected before repair.
5. Apply the producer and refresh the dimension, then the twelve reviewed functions, validating
   each step. Apply dbt separately through its runbook and `dbt_*` dataset guard.

Stop and investigate any unexpected runtime error, interface change, duplicate key, unexplained
aggregate change or missing known warehouse. Do not continue application on failed acceptance.

## Acceptance and observation

After application, read back the deployed definitions and check the eight-column dimension and
unchanged function interfaces. Require unique/nonblank IDs, policy coverage and correction of
the seven expected classification mismatches. Test v2 modes 0/1/3 with representative dates:
online and unaffected Thai results should preserve totals; restored ecommerce/store rows must
be attributable to the intended IDs, not merely accepted because totals increased.

Observe the first scheduled warehouse refresh for job errors and repeat key/policy checks.
Validate dbt adapter/post-hook behavior separately. Production permissions, scheduler execution,
persistent-table concurrency and dbt adapter execution remain untested application-time concerns.
Temporary guard tests did not inject a failure after a successful write. No production monitoring
or successful rollout is claimed by this report.

## Rollback plan

Trigger rollback for an application failure or a confirmed data-integrity/interface/aggregate
regression. Stop further application and coordinate scheduled writers before restoring data.

1. Restore the exact saved routine definitions for the objects already replaced, using replacement
   DDL. Fresh pre-application captures take precedence if legitimate live changes were reconciled.
2. If dimension data changed, restore it from the verified pre-change backup while accounting for
   legitimate post-backup updates. Routine rollback alone cannot undo dimension changes.
3. Keep dbt rollback separate and limited to its own datasets/model state. Preserve raw and staging.
4. Verify definition readback, dimension keys/classifications and representative aggregates; retain
   backups until the restored state is accepted. Restoring the original VN store v2 definition
   also restores its known UUID-versus-name filter defect.

Retained routine capture:
[build-live-warehouse-routines.json](/Users/tony.pham/.bb/thread-storage/thr_qjwbpax4cj/warehouse-id-plan/build-live-warehouse-routines.json).
All thirteen pending-object DDL hashes match this capture. Capture SHA-256:
`1d19f4ea6909e4916429ff9dbdae448188ed446bc2abc8958b8daaa2350faac2`.
No rollback has been executed and no recovery-time guarantee is claimed.
