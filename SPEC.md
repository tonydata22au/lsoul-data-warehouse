# Spec: Stable warehouse identity

Current status: canonical-name continuation implemented on 2026-11-02; Verify and Review remain.
See [Build report](tasks/warehouse-name-build-report.md). Production is unchanged.
The preceding predicate/dimension work completed Build, Verify and Review with Ship readiness GO;
that verdict does not cover this extension. Production application remains outstanding.
Agent Flow supplies the Plan → Build → Verify → Review → Ship gates; no separate opt-in gate applies.

## Current continuation: canonical warehouse names in every function

This section extends and takes precedence over the earlier display-name exclusions below.
Continue the prepared work from thread `thr_qjwbpax4cj`, preserving its SQL, producer, dbt policy,
tests, immutable snapshots and current branch. The user now requires warehouse names used in
reporting functions to resolve from `core_pancake.core_warehouse`; warehouse selection must use
the corresponding verified IDs. See [live scope inventory](tasks/warehouse-name-inventory.md).

### Objective and verified scope

Prepare source updates for 37 functions: 29 sales leaves and eight inventory/report consumers.
Five other functions inherit corrected names; seven additional consumers need regression checks.
All 64 accessible functions were inventoried across 22 datasets in `asia-southeast1`. Coverage
includes SELECT-star propagation, not only textual `warehouse_name` matches. No inaccessible
resources are implied by this inventory.

The previous twelve predicate fixes remain necessary: fresh live hashes still match their earlier
baselines. The warehouse-procedure baseline also matches. Nineteen current dimension rows have
nineteen distinct nonempty IDs matching the existing policy. Historical aliases were re-read from
the prior thread's same-day warehouse-only capture; no fuzzy identity mapping is needed.

### Contracts and assumptions

1. `warehouse_name` is the current dimension display attribute for the **warehouse ID returned
   in that same row**. Where outputs use `oi.warehouse_id`, resolve names by the item ID even
   when old code paired it with a header name. Preserve `o.warehouse_id` for header-based
   membership and shipping rules. Do not make item identity control existing header filters.
2. Resolve ordinary names with a cardinality-preserving dimension lookup. A LEFT JOIN is preferred
   when it fits the query grain; preserve unmatched fact rows and return NULL for their unknown
   names. Do not use old fact names, literal aliases, fuzzy matches or guessed IDs as fallbacks.
   Dimension uniqueness is a precondition; do not hide duplicate/conflicting names with ANY_VALUE.
3. Keep deliberate empty ID/name fields in modes without warehouse grain, including sales v2
   modes 0/1 and inventory summary aggregate modes. Never assign one warehouse to a total row.
4. Keep fixed reporting labels (`Store Nguyễn Trãi`, `Emsphere`, channel levels, countries) and
   classify them by existing verified IDs. Display fallbacks derived from an actual warehouse
   must use the appropriate dimension name. Combined-source inventory labels currently occupying
   `warehouse_name` become canonical names; preserve their independent stock/date-cutover logic.
5. Preserve source-system calculation identity. Dianplus inventory has a source warehouse-name
   partition in LAG; it is not the Pancake reporting warehouse. Retain that source partition under
   an explicit internal alias such as `source_warehouse_name`. Do not collapse multiple physical
   source streams onto the single China reporting ID. Returned names still come from the dimension.
6. Keep signatures, column names/order/types, ID outputs, modes, monetary formulas, quantities,
   status/source filters and date windows. Validate aggregate parity by stable identity, accounting
   separately for intended renamed-warehouse recovery from the earlier predicate repair. Avoid
   name changes splitting warehouse aggregates or multiplying joins; preserve source-grain windows.
7. Existing China/Thai reporting IDs remain unchanged: China literals use
   `76be7836-6dc5-4b1c-9e48-b18e43127453`; Thai commerce/online/inventory literals use
   `878504e9-fb75-4870-8504-b2ecdbc097ba`. Their live SQL already establishes these identities,
   including aliases `Kho Ecommerce Thailand` and `Kho Thái Lan` absent from the current dimension.
8. Functions reading persisted report tables resolve the dimension themselves. This extension
   does not rebuild those tables. Existing dimension/dbt work remains pending and is preserved;
   no new dbt or ingestion changes are required for the added function-name contract.

### Implementation style and structure

Use existing maintained paths identified by CREATE object name and `sql/source_provenance.json`.
Add missing exact-object sources as `sql/functions/reportdb.<object>.sql`; one object per file.
Do not change `sql/live/` or represent prepared SQL as observed production. Keep changes focused.
Tests belong under `tests/`; migration guidance is `docs/warehouse-identity.md`; detailed tasks
are in [tasks/todo.md](tasks/todo.md). No new runtime lookup table or helper function is required.

Illustrative shape (integrate at the function's existing warehouse grain):

```sql
SELECT oi.warehouse_id, w.warehouse_name
FROM `marine-cycle-484213-b4.core_pancake.core_order` o
JOIN `marine-cycle-484213-b4.core_pancake.core_order_item` oi ON oi.order_id = o.order_id
LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_warehouse` w
  ON w.warehouse_id = oi.warehouse_id
WHERE o.warehouse_id = '3fb24787-3208-4fb7-9580-24a3754e51d6'
```

### Validation and success criteria

- Every one of the 42 name-related functions is accounted for: 37 direct fixes and five inherited
  paths. All warehouse-grain output names originate from the dimension by the corresponding ID.
  No executable warehouse-selection predicate uses a display name. Source-only partition keys,
  comments and intentional blank aggregate fields are classified explicitly, not blanket-exempted.
- Rename, reused-name, unknown/null/blank ID, header/item disagreement and duplicate-dimension
  fixtures exercise actual proposed SQL fragments or bodies. Verify that totals and row membership
  do not depend on display-name changes. Preserve all existing predicate/dimension tests.
- Check all UNION branches and modes, inventory cutover boundaries, multiple source warehouses,
  NULL names and persisted-report stale names. Validate output types/order and no join fanout.
- Regression coverage includes the full 49-function dependency closure. Use bounded query-body
  dry runs for GoogleSQL compilation; compile an expanded proposed dependency graph where feasible,
  because testing unchanged live callees cannot prove the proposed graph. Report any limitations.
- Run `python3 scripts/validate_sql_sources.py`, `python3 scripts/validate_repo.py`,
  `python3 -m unittest discover -s tests`, and `git diff --check`. Imports are unnecessary when
  only SQL/docs/tests change. Existing whole-body assertions must allow only reviewed name-lookup
  changes, preserving checks on unrelated logic; do not broadly mask JOINs or warehouse tokens.
- Save exact per-function live rollback definitions and compare hashes before later application.
  Preserve routine options/access assumptions; verify caller access to the newly referenced dimension.
  Readiness requires pending-source provenance, passing checks and independent review.

Always preserve the current branch and local work. Clarify any newly discovered conflicting
identity before modifying that slice; there is no unresolved identity decision in the captured
scope. Never run production DDL/DML, deploy routines, refresh reports, run ingestion, switch
branches, commit or push in this Agent Flow. The user requested live updates, but this flow's
explicit no-deployment boundary means production application must remain an outstanding action.

## Earlier predicate and dimension specification (retained)

## Optimised user prompt

In BigQuery project `marine-cycle-484213-b4`, inventory the deployed functions that use
hardcoded warehouse names in executable filters. Resolve each historical name to a verified
`warehouse_id` using `core_pancake.core_warehouse` and warehouse-only history. Replace those
predicates with ID predicates, including related warehouse-dependent reporting classifications,
while preserving function signatures, output columns, joins, Boolean logic, reporting labels,
date windows and calculations. Names remain display attributes.

Refactor `core_pancake.core_warehouse` and its producer
`core_pancake.sp_pancake_core_warehouse_insert` to maintain one deterministic current row per
warehouse ID and stable country/type classifications across renames. Apply the same policy to
BB project `proj_3598auxu2c` (`lsoul_dbt`). Update source files, documentation and meaningful
regression coverage. Validate mapping completeness, rename invariance, deduplication and
reporting parity. Report separately what was prepared, tested and applied to production.

## Objective and scope

LSOUL reporting must keep selecting the same business warehouses after a rename. This is one
capability spanning reporting SQL, its warehouse dimension and the parallel dbt implementation.
The user requests live corrections as the eventual outcome; this Agent Flow is limited to
preparing, verifying and reviewing changes, with Ship assessing readiness only, never deploying.
Production remains an explicit outstanding action at the end of this flow.

Assumptions:

- Warehouse IDs are the existing stable STRING identity. Keep names and name-derived codes
  as presentation fields. Preserve the existing eight-column dimension interface.
- Preserve the established business classifications through the recent rename. Do not infer a
  physical relocation from new labels such as `CN – Backup Stock (VN)`.
- Preserve current behavior where historical names imply conflicting business classifications;
  specifically the head-office ID stays VIETNAM/P pending separate business reclassification.
- Preserve default VIETNAM/P behavior for newly encountered unmapped IDs for compatibility,
  but report unmapped IDs in validation. No runtime name-matching fallback is allowed.
- Preserve existing activity/timestamp policy and source windows. Deduplication and ID-based
  classification are intentional changes; unrelated financial, timezone and null/source logic
  corrections are outside this request.

## Verified scope

Live inspection found 22 accessible datasets, all in `asia-southeast1`. Of 47 routines mentioning
warehouse names, 41 are table functions and six procedures. Twelve table functions have active
name filters, grouped below. Inventory describes accessible resources, not proof of hidden IAM coverage.

| Family | Deployed objects in `reportdb` | Warehouse IDs selected |
| --- | --- | --- |
| VN ecommerce | `fn_sale_ecom_vn`, `fn_sale_ecom_vn_product`, `fn_sale_ecom_vn_v2` | `3fb24787-3208-4fb7-9580-24a3754e51d6` |
| VN online | `fn_sale_online_vn`, `fn_sale_online_vn_product`, `fn_sale_online_vn_v2` | `cf854971-c137-4e23-86ec-4bd8fbed6990`, retaining the existing OR with source membership |
| VN stores | `fn_sale_store_vn`, `fn_sale_store_vn_product`, `fn_sale_store_vn_v2` | `4a93fada-d892-4bbd-8547-ec505e6104df`, `c9aea4ce-e71e-404e-b7c1-8d6ff342d748` |
| Thai stores | `fn_sale_store_thai`, `fn_sale_store_thai_product`, `fn_sale_store_thai_v2` | `ad07f1c9-84be-4c4d-bc5b-4de980ffb97e`, `490ded40-64ba-4424-aaed-399abbf13fbb`, `133983a4-ff7d-4861-805c-0a1bdd51795f` |

Every predicate uses order-header alias `o`; do not replace it with item alias `oi`.
All six store functions also classify report labels by names. Convert those decisions to the
same IDs, retaining existing labels and fallback display behavior.

The live VN store v2 function, altered 2026-11-02, currently compares `o.warehouse_name` with
UUID strings. Fix the column to `o.warehouse_id` without reverting its other live edits.
The live warehouse procedure, altered 2026-10-29, no longer contains the logging calls present
in the October 28 snapshot. Use the fresh definition; do not restore removed logging.

## Tech stack and structure

- BigQuery GoogleSQL, project `marine-cycle-484213-b4`, region `asia-southeast1`.
- Python standard-library repository tooling/tests; dbt BigQuery/Jinja in sibling `lsoul_dbt`.
- `sql/functions/`: maintained deployment sources. Three affected existing files use short
  filenames but create `_v2` objects; add exact-object files for the nine missing functions.
- `sql/procedures/core_pancake.sp_pancake_core_warehouse_insert.sql`: maintained producer source.
- `sql/live/`: immutable October 28 observed snapshot, protected by manifest hashes.
- `sql/core/core_pancake.core_warehouse.sql`: historical June 2 CTAS, not the current producer.
- `tests/`, `docs/`, `tasks/`: regression checks, migration notes, planning artifacts.
- Sibling `lsoul_dbt/models/core/pancake/core_pancake__warehouse.sql`: parallel dbt dimension;
  its current merge already chooses one row per ID. Existing YAML tests assert ID uniqueness
  and non-nullness. dbt must continue writing only to `dbt_*` datasets.

## Commands

Warehouse repository, offline:

```sh
python3 scripts/validate_repo.py
python3 -m unittest discover -s tests
git diff --check
```

Sibling dbt repository, offline (use a separate log path to preserve dirty `logs/dbt.log`):

```sh
DBT_LOG_PATH=/tmp/lsoul-warehouse-id-dbt-logs DBT_PROFILES_DIR=profiles uv run dbt parse
uv run python scripts/check_project.py
uv run python scripts/render_models.py
uv run python -m unittest discover -s scripts -p 'test_*.py'
uv run sqlfluff lint models
uv run python scripts/gen_inventory.py --check
pnpm --dir data-lineage test
pnpm --dir data-lineage generate
pnpm --dir data-lineage build
```

Metadata retrieval and bounded SELECT diagnostics are within this request. Example inventory:

```sh
bq --project_id=marine-cycle-484213-b4 --location=asia-southeast1 --format=prettyjson query --use_legacy_sql=false --maximum_bytes_billed=1000000000 --label=datacloud:codex --max_rows=1000 'SELECT routine_schema, routine_name, routine_type, routine_definition, ddl, last_altered FROM `marine-cycle-484213-b4.region-asia-southeast1.INFORMATION_SCHEMA.ROUTINES` WHERE REGEXP_CONTAINS(LOWER(routine_definition), r"warehouse_name|warehousename") ORDER BY routine_schema, routine_name'
```

Do not execute production CREATE/REPLACE/CALL/UPDATE/MERGE, dbt builds or deployment scripts in this flow.
BigQuery dry runs contact the service; validate selected query bodies with an explicit cost cap,
not by executing DDL. Offline parsing alone is not proof of BigQuery execution correctness.
Synthetic procedure checks may execute anonymous blocks against disposable TEMP tables and a TEMP
test UDF, with no persistent resource references or production writes. Verify used this boundary
to exercise transaction/control flow that dry runs skip; see [the verification report](tasks/verify-report.md).

## Code style

Preserve surrounding formatting and fully qualified names. Representative intended predicate:

```sql
AND (
  o.order_sources_name IN ('Website', 'Facebook', 'Webcake', 'Instagram', 'Zalo')
  OR o.warehouse_id = 'cf854971-c137-4e23-86ec-4bd8fbed6990'
)
```

## Testing strategy and acceptance

1. Inventory all accessible live functions again before finalizing; no executable name-based
   warehouse selection/classification remains in the twelve targets. Exclude comments and
   display projections from this rule. Preserve aliases, OR grouping, signatures and schemas.
2. Exercise each function family with synthetic old name/new name, a different ID reusing the
   old name, null/unknown ID, and order/item warehouse disagreement. Test v2 modes 0, 1 and 3.
   Existing reporting membership is unchanged for original names; renamed rows remain included.
3. Procedure source chooses exactly one row per nonempty ID, using newest staging load, newest
   inventory event, then an explicit stable tie-breaker. An all-null name must not erase an existing
   display name. Test duplicate/mixed-name input, timestamp ties, stale/missing source, absent
   warehouses, inactivity and reactivation. Protect the update atomically; avoid delete-then-insert gaps.
4. Classify all 19 verified IDs with a documented ID policy. Apply corrections to existing
   dimension rows even if an ID is absent from today's staging partition. Latest display labels
   can change; country/type cannot change merely because the label changes. Check unknown IDs.
5. dbt uses the same policy without live-dataset dependencies. Preserve its merge, source-window,
   eight-column interface, clustering and documented timestamp differences; retain existing key tests.
6. Preserve snapshot hashes and provenance. Tests must distinguish pending maintained sources
   from observed snapshots explicitly, rather than silently making proposed SQL appear deployed.
7. Offline suites and rendering pass. Any read-only aggregate validation uses warehouse-only or
   aggregate output with no customer records. Classify changed totals as intended recovered rows
   versus regressions; the already broken live function is not an equality oracle.
8. Ship records deployment as outstanding, plus readiness, blockers and rollback material.

## Boundaries

- Always: use each checked-out `main` branch; preserve existing changes; minimize data retrieval;
  keep snapshot provenance; base changes on fresh live definitions; separate source, test and live status.
- Resolve before changing scope: conflicting warehouse identity mapping or a proposed business
  reclassification without evidence. Preserve established behavior for such cases meanwhile.
- Never: read `.env` or credentials, expose customer rows, delete raw data, alter unrelated logic,
  switch branches, push/PR/commit without instruction, repoint reportdb to dbt, or deploy in this flow.

## Open items

No user decision blocks implementation planning. Head-office classification ambiguity is handled
by retaining current VIETNAM/P; changing it is outside this repair. New-ID onboarding remains an
operational obligation and must be documented. Production application is prohibited by this flow,
not awaiting a new permission question from the user.
