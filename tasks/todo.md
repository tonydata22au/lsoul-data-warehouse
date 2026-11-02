# Tasks: Stable warehouse identity

Current continuation: canonical names are built; N01–N16 are implemented. N17 Verify/Review remains;
the completed original tasks are retained afterward. See the current sections of [SPEC.md](../SPEC.md),
[plan.md](plan.md), and [scope inventory](warehouse-name-inventory.md). Agent Flow controls gates;
production application remains outside this flow.

## N01: Fix the name/identity contract and regression fixture

- [x] Resolve maintained source paths by CREATE object name, preserving the twelve pending fixes.
- [x] Add focused canonical-display fixtures for renames, item/header disagreement, unknown IDs,
      duplicate dimension rows and aggregate blanks; preserve existing tests.
- [x] Preserve exact fresh DDL/hash references and classify internal source partition keys explicitly.

Acceptance: the tested contract matches SPEC.md and every direct target has an unambiguous baseline.
Verification: focused unittest discovery; snapshot/provenance checks before further source edits.
Dependencies: none. Files: one shared test/fixture module, scope/contract docs if needed (at most 3).
Size: M. No runtime helper function or dimension table is introduced.

## N02: VN ecommerce names

- [x] Update `fn_sale_ecom_vn, fn_sale_ecom_vn_product, fn_sale_ecom_vn_v2`.
- [x] Resolve names by output warehouse ID; retain verified header-ID ecommerce membership.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

## N03: VN online names

- [x] Update `fn_sale_online_vn, fn_sale_online_vn_product, fn_sale_online_vn_v2`.
- [x] Resolve output names and preserve the source-membership OR warehouse-ID condition.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

## N04: VN store names

- [x] Update `fn_sale_store_vn, fn_sale_store_vn_product, fn_sale_store_vn_v2`.
- [x] Keep ID-based store labels and corrected UUID predicate; resolve projected names and display fallbacks.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

### Checkpoint after N04

- [x] Completed slices pass their focused tests; intended name changes are isolated.
- [x] Stable identity, row counts, totals and blank aggregate contracts remain verified.
- [x] No production objects, immutable snapshots or unrelated local changes were modified.

## N05: Thai store names

- [x] Update `fn_sale_store_thai, fn_sale_store_thai_product, fn_sale_store_thai_v2`.
- [x] Preserve three store memberships and fixed reporting labels; canonicalize actual warehouse display names.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

## N06: VN wholesale names

- [x] Update `fn_sale_wholeshale_vn, fn_sale_wholeshale_vn_product, fn_sale_wholeshale_vn_v2`.
- [x] Replace order/item display sources without adding new warehouse-membership restrictions.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

## N07: China ecommerce names

- [x] Update `fn_sale_ecom_china, fn_sale_ecom_china_product, fn_sale_ecom_china_v2`.
- [x] Resolve existing China backup ID to its dimension name in every source branch; keep quantities/currency logic.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

## N08: China manual-commerce names

- [x] Update `fn_sale_ecom_taobao_tmall_manual_china, fn_sale_ecom_taobao_tmall_manual_china_product, fn_sale_ecom_taobao_tmall_manual_china_v2`.
- [x] Resolve the existing China backup ID; preserve manual-data handling and sales formulas.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

### Checkpoint after N08

- [x] Completed slices pass their focused tests; intended name changes are isolated.
- [x] Stable identity, row counts, totals and blank aggregate contracts remain verified.
- [x] No production objects, immutable snapshots or unrelated local changes were modified.

## N09: China store names

- [x] Update `fn_sale_store_china, fn_sale_store_china_product, fn_sale_store_china_v2`.
- [x] Resolve the existing China backup ID; preserve refunds, discounts and country/source classifications.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

## N10: Thai ecommerce names

- [x] Update `fn_sale_ecom_thai, fn_sale_ecom_thai_product, fn_sale_ecom_thai_v2`.
- [x] Resolve the explicit Thai backup ID, replacing both legacy Ecommerce and Backup label variants.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

## N11: Thai online names

- [x] Update `fn_sale_online_thai_product, fn_sale_online_thai_v2`.
- [x] Resolve the explicit Thai backup ID; retain ONLINE source matching and financial/date logic.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 2 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

### Checkpoint after N11

- [x] Completed slices pass their focused tests; intended name changes are isolated.
- [x] Stable identity, row counts, totals and blank aggregate contracts remain verified.
- [x] No production objects, immutable snapshots or unrelated local changes were modified.

## N12: Inventory source names

- [x] Update `fn_china_product_inventory, fn_thailand_product_inventory, fn_product_variations_warehouse_summary`.
- [x] Resolve China/Thai reporting names and use the existing dimension join for variations. Preserve Dianplus source-name LAG partitions under an explicit internal alias.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

## N13: Shipment and persisted-report names

- [x] Update `fn_product_inventory_overseas_shipment, fn_assortment_seg_cont_by_warehouse, fn_stats_product_v2`.
- [x] Resolve names by returned IDs, including stale persisted names. Preserve header shipment rules and warehouse-less summary rows; no report refresh.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N01. Files: the 3 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

### Checkpoint after N13

- [x] Completed slices pass their focused tests; intended name changes are isolated.
- [x] Stable identity, row counts, totals and blank aggregate contracts remain verified.
- [x] No production objects, immutable snapshots or unrelated local changes were modified.

## N14: Inventory summary canonical names

- [x] Update `fn_product_inventory_summary`.
- [x] Replace only warehouse-name source/combined-label logic; preserve stock cutovers, window partitions and aggregate blank output.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N02–N13. Files: the 1 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

## N15: Inventory summary v2 canonical names

- [x] Update `fn_product_inventory_summary_v2`.
- [x] Canonicalize display lookup/fallback and combined-label overrides; preserve source composition, fill logic, stock rules and aggregate blanks.
- [x] Verify rename invariance, no join fanout, output schema and non-name behavior.

Acceptance: every warehouse-grain name resolves through core_warehouse by the corresponding ID;
unmatched IDs retain rows with NULL names; signatures/modes and unrelated calculations remain intact.
Verification: focused SQL-semantic fixtures; review the exact live-to-proposed diff; GoogleSQL
query-body dry runs during Verify. Sales v2 modes 0/1/3 and inventory mode blanks are covered.
Dependencies: N02–N13. Files: the 1 named SQL source(s), resolved by object name, plus
one focused test module (at most 4 files). Source hashes are integrated centrally in N16. Size: M.

### Checkpoint after N15

- [x] Completed slices pass their focused tests; intended name changes are isolated.
- [x] Stable identity, row counts, totals and blank aggregate contracts remain verified.
- [x] No production objects, immutable snapshots or unrelated local changes were modified.

## N16: Integrate scope, provenance and inherited paths

- [x] Update pending source hashes/status for all 37 direct targets without changing live snapshots.
- [x] Extend strict source checks and test all five inherited paths, including fn_stats_product SELECT-star.
- [x] Update warehouse migration guidance with name semantics, null behavior, coverage and rollback list.

Acceptance: 37 direct targets and five inherited paths are accounted for; all seven additional
aggregate consumers remain in the regression list. Unlisted source edits and changed snapshots
still fail. Existing function tests allow only reviewed canonical-name changes, not broad masking.
Verification: `python3 scripts/validate_sql_sources.py`; focused provenance/mutation checks and
wrapper schema/branch checks. Dependencies: N02–N15. Files: provenance manifest, source coverage
validator/tests, migration guide (at most 5). Size: M. One owner integrates shared files.

## N17: Verify the proposed graph and prepare application handoff

- [ ] Run required repository checks and targeted BigQuery SELECT-body dry runs for proposed SQL.
- [ ] Validate 49-function dependency coverage, all modes, cutover boundaries and source partitions.
- [ ] Record independent review/readiness, all limitations, exact rollback material and production still pending.

Acceptance: test evidence supports canonical names, ID selection, no fanout and unchanged unrelated
metrics. Compile proposed dependencies where possible; never call live wrappers and present them
as tests of undeployed leaves. Baseline drift, ambiguous mapping or unresolved failed checks block readiness.
Verification: `python3 scripts/validate_repo.py`; `python3 -m unittest discover -s tests`;
`python3 scripts/validate_sql_sources.py`; `git diff --check`; bounded dry-run/aggregate evidence.
Dependencies: N16. Files: current continuation verification/review/readiness reports and migration
handoff (at most 4; preserve original reports as historical). Size: M. No deploy or table refresh.

## Continuation completion checkpoint

- [ ] Every name path and direct function is covered; meaningful tests and required checks pass.
- [ ] Independent Review accepts the extension; Ship assesses readiness and rollback only.
- [ ] Production state is reported accurately; no live update claimed from source preparation.

## Original completed tasks (historical)


Ship handoff. Implementation, verification and review are complete; readiness is GO for controlled
application. Production application remains outstanding. Follow [plan.md](plan.md) and
[SPEC.md](../SPEC.md); Agent Flow controls stage progression. No deployment in this flow.

## Task 1: Record verified ID policy and current source baselines

- [x] Save the nineteen-ID policy and function membership groups as reviewed configuration.
- [x] Capture exact current twelve-function/procedure hashes; retain unrelated live edits.
- [x] Record original aliases and current labels as evidence only, including head-office P decision.

Acceptance: every selected legacy name resolves to exactly one verified ID; all nineteen IDs are
covered without runtime name matching; current live definitions are the implementation baseline.
Verification: policy uniqueness/coverage checks and baseline-hash comparisons with thread artifacts.
Dependencies: none. Files: proposed policy/config, baseline metadata and migration guide (3). Size: M.

## Task 2: Represent pending sources without changing observed history

- [x] Add an explicit proposed-source manifest outside `sql/live/`.
- [x] Extend snapshot parity checks to validate intentional source divergence and its hashes.
- [x] Keep every October 28 snapshot file/hash and unaffected parity assertion intact.

Acceptance: an unlisted source edit still fails; altered snapshot bytes still fail; a declared pending
source records object, source path, observed baseline hash, proposed hash and pending status.
Verification: meaningful positive/negative manifest tests; `python3 -m unittest discover -s tests`.
Dependencies: 1. Files: pending manifest, `tests/test_warehouse_snapshot.py`, focused tests, sync guide
(4). Size: M. This task is not permission to weaken integrity checks.

## Checkpoint A: Policy and provenance

- [x] IDs and current live baselines verified; no unresolved identity ambiguity.
- [x] Snapshot checks distinguish observed versus pending sources; no production mutations.

## Task 3: VN ecommerce membership survives renames

- [x] Replace the header name predicate with its verified ID in base, product and v2 functions.
- [x] Preserve signatures, columns and unrelated source/status/money filters.

Acceptance: old/new names for the selected ID both qualify; an unrelated ID with the old name does not.
Verification: synthetic membership and schema checks; v2 modes 0/1/3.
Dependencies: 1, 2. Files: existing `sql/functions/fn_sale_ecom_vn.sql`, new exact-object base/product
sources and a focused test module (4). Size: M.

## Task 4: VN online membership survives renames

- [x] Replace the warehouse predicate in all three functions, preserving the source-membership OR.
- [x] Cover rows qualifying solely through source, solely through warehouse, or through neither.

Acceptance: Boolean behavior and order-header alias remain unchanged except rename resilience.
Verification: synthetic OR/null/header-versus-item cases; signature/schema checks and v2 modes.
Dependencies: 1, 2. Files: existing online v2 source, two new exact-object sources, focused tests (4).
Size: M.

## Checkpoint B: Ecommerce and online

- [x] Focused checks pass; no runtime warehouse-name comparisons remain in these six functions.
- [x] Review minimal SQL changes and preserve snapshot integrity.

## Task 5: VN store membership and labels survive renames

- [x] Replace filters and label CASE predicates in all three functions with verified IDs.
- [x] Correct the current live v2 UUID/name-column mismatch; preserve report labels.

Acceptance: Nguyễn Trãi and POP-UP membership/labels are stable for historical and renamed rows;
no unrelated live edits are reverted. Verification: synthetic cases, baseline diff, v2 modes/schema.
Dependencies: 1, 2. Files: existing VN store v2 source, two new exact-object sources, focused tests
(4). Size: M.

## Task 6: Thai store membership and labels survive renames

- [x] Add maintained base/product/v2 sources from fresh live DDL.
- [x] Convert filter, source classification and level-label name patterns to the three IDs.

Acceptance: EmSphere, Central Ladprao and Central World retain exact existing labels and membership.
Verification: renamed/unrelated/null fixtures; signature/schema and v2 mode checks.
Dependencies: 1, 2. Files: three exact-object sources and focused tests (4). Size: M.

## Task 7: Synchronize function manifest and coverage

- [x] Register all twelve final source hashes in the pending manifest.
- [x] Verify coverage against fresh live routine inventory, including missing curated sources.
- [x] Document commented-only/display-only uses excluded from the predicate rule.

Acceptance: all twelve targeted functions accounted for; remaining executable name predicates are
absent; unaffected files retain exact snapshot parity. Verification: full warehouse offline suite.
Dependencies: 3–6. Files: pending manifest, coverage test, migration guide (3). Size: M.

## Checkpoint C: Complete reporting layer

- [x] Four family regressions and manifest/coverage checks pass.
- [x] Function interfaces, labels and financial logic preserved; renamed rows recover as intended.

## Task 8: Maintain a stable current warehouse dimension

- [x] Replace delete/insert DISTINCT behavior with deterministic per-ID staged upsert and atomicity.
- [x] Apply the verified country/type policy to incoming and existing IDs, preserving display columns.
- [x] Cover stale/missing source, null names, tied events, duplicate input, inactivity and reactivation.

Acceptance: eight-column contract and source/activity/timestamp policies preserved; one row per ID;
renames cannot alter classification; removed live logging is not restored; unknown IDs are reported
and keep documented constant defaults. Verification: synthetic SQL semantics, target uniqueness
preflight, schema compatibility and optional bounded query-body dry runs (no DML execution).
Dependencies: 1, 2. Files: warehouse procedure, focused test module, pending manifest, migration guide
(4). Size: M. Do not run the historical June 2 CTAS.

## Task 9: Port stable warehouse policy to dbt

- [x] Update the warehouse model to use the same ID policy, retaining its merge and load-window rules.
- [x] Add a local macro/config if needed and test policy parity without a live core dependency.
- [x] Preserve eight columns/clustering and simplify activity grouping to ID.

Acceptance: rename-invariant classification matches the procedure; existing key tests remain;
dbt-only destinations and pre-existing log changes are preserved. Verification: focused offline
regressions, parse/render and schema check; no dbt build/run/test against BigQuery.
Dependencies: 1, 8. Files in sibling dbt: model, optional macro/config, regression tests, YAML (up to 4).
Size: M.

## Checkpoint D: Dimension and dbt agreement

- [x] Uniqueness, deduplication, latest-label and classification tests pass.
- [x] All nineteen policy rows agree across implementations; timestamp differences remain documented.

## Task 10: Update dbt documentation and generated lineage

- [x] Update Pancake parity notes/model descriptions and inventory when relevant.
- [x] Regenerate lineage using truthful observed source and dbt manifest inputs.
- [x] Run all mandated offline dbt and lineage checks from SPEC.md with a separate dbt log path.

Acceptance: docs describe intentional changes and limitations; generated outputs are reproducible;
lineage does not represent pending SQL as deployed. Verification: parse, check_project, render_models,
macro tests, SQLFluff, inventory check and lineage test/generate/build commands.
Dependencies: 7, 9. Files: parity notes, inventory, schema docs and generated lineage artifacts;
if generator affects more than five files, split its generated-output review into separate batches.
Size: M per batch.

## Task 11: Complete validation and application handoff

- [x] Run warehouse static checks/unit suite/diff checks and preserve exact exit codes.
- [x] Prepare SQL validation/preflight and ordered application/rollback instructions without execution.
- [x] Record review/readiness, unresolved limits and production application still outstanding.

Acceptance: each acceptance condition has evidence or a named gap; exact function/producer rollback
baselines preserved; no deployment or production table repair claimed. Verification: both repo diffs,
all required checks, optional bounded aggregate validation and Agent Flow independent Review.
Dependencies: 7, 8, 10. Files: migration guide, plan/task status and validation report (up to 4). Size: M.

## Checkpoint E: Ready for review and readiness assessment

- [x] All completed checks pass; failed checks are fixed and rerun or explicitly block readiness.
- [x] Independent code reviews completed with no unresolved blockers; Agent Flow advanced to Ship.
- [x] Ship gives go/no-go, rollback plan and the outstanding production-application boundary.

Main Review: four independent domain/provenance reviews found no blockers; two minor clarity
findings were fixed and checks rerun. See [review-report.md](review-report.md).
Ship: GO for prepared-source readiness; backup/preflight/application/readback remain outside this
flow. See [ship-report.md](ship-report.md) for prerequisites, acceptance and rollback.
