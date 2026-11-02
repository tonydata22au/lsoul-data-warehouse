# Implementation plan: Stable warehouse identity

Specification: [SPEC.md](../SPEC.md). Tasks: [todo.md](todo.md).
Current stage: canonical-name Build implemented; see [Build report](warehouse-name-build-report.md).
Earlier Build/Verify/Review/Ship reports
cover the predicate/dimension work only. Production is unchanged.

## Current continuation plan: canonical names

The new requirement extends the same warehouse-identity capability. Preserve completed work;
do not restart or replace it. The authoritative extension is at the top of SPEC.md. The
[per-function inventory](warehouse-name-inventory.md) records 37 direct changes, five inherited
paths and seven further aggregate consumers, with exact live hashes.

### Sequence and ownership

`fresh live baselines + verified ID policy → display/key contract → leaf families → inventory summaries → wrapper regression → provenance/review/readiness`

1. Establish a shared canonical-name fixture/contract and preserve all existing identity tests.
   Record exact maintained paths and fresh DDL baselines. The twelve pending functions and producer
   have not drifted; continue their prepared changes. Resolve the other 25 direct targets from live
   bodies, not outdated snapshots. Audit source comments before adding maintained files.
2. Update five Pancake sales families in three-function slices: VN ecommerce, online, store,
   wholesale, and Thai store. Display lookup follows the output ID; membership stays header-based.
3. Update three China families (ecommerce, manual Taobao/Tmall, stores), then Thai ecommerce and
   Thai online. Preserve explicit mapped IDs; replace old literal names through the dimension.
4. Update China/Thai inventory leaves and variation-warehouse summary. Keep Dianplus source-stock
   partitioning distinct from its Pancake reporting ID. Preserve activity/type/country behavior.
5. Update overseas shipment, assortment and stats-v2 materialized-report consumers. They must
   independently resolve current names; do not trigger a report-table refresh.
6. Update inventory summary and v2 separately after their leaves. Remove name-only combined-source
   overrides, retain stock rules and summary blanks. Check aliases, grouping and window grain.
7. Validate all five inherited paths and seven additional downstream consumers. No textual edits
   are required solely to add redundant dimension joins to already-canonical wrapper output.
8. One integration owner updates pending source hashes, coverage and migration documentation.
   Complete offline validation, bounded GoogleSQL checks and independent Review; Ship assesses
   readiness only. Do not apply production changes.

Independent leaf-family slices can run in parallel after the shared contract is fixed, with
separate SQL/test ownership. Inventory summaries depend on leaf work. Manifest changes, shared
test helpers, any dimension changes and final validation remain sequential under one owner.
Task details and checkpoints are N01–N17 at the top of todo.md; each implementation slice touches
at most three SQL files plus focused tests. The preceding producer/dbt changes are retained.

### Decisions, risks and checkpoints

| Concern | Required treatment |
| --- | --- |
| Existing item ID/header name mismatch | Resolve by returned item ID; preserve header ID predicates and shipment logic |
| Missing dimension row | LEFT JOIN/preserving lookup; NULL name, retain fact row, report coverage gap |
| Duplicate dimension ID | Block readiness; retain prior deterministic producer work; do not choose arbitrary display values |
| Unknown new alias | Use actual ID/history evidence; ask only if conflict remains; no fuzzy matching |
| Names split aggregate groups | Review stable-ID grain and distinct counts, compare metrics independently of display names |
| Source name used by Dianplus LAG | Keep source key explicitly internal; resolve only reporting display through core_warehouse |
| Persisted report carries stale name | Join dimension in its function consumer; no production report rebuild |
| Aggregate-mode blank names | Preserve blanks and signatures; no invented warehouse for combined totals |
| New dimension dependency | Check query compilation and existing authorized-routine/caller access expectations |
| Provenance/test weakening | Immutable snapshot, explicit pending hashes, narrow semantic assertions and mutation checks |

Checkpoints follow early Pancake slices, completed sales leaves, inventory leaves, summaries and
integrated validation. Extend the prior rollback plan to all 37 function DDLs; unchanged wrappers
need no DDL rollback. If the existing dimension migration is later applied, its separate table
backup/producer rollback remains required. Do not restore functions from the October snapshot.

### Planning evidence and limits

Fresh read-only discovery on 2026-11-02: 22 accessible datasets, 93 routines, 64 functions; all
datasets are in asia-southeast1. Scope and baseline assertions passed. Current dimension IDs match
the nineteen-ID policy, and twelve function/procedure baselines are unchanged. Historical mapping
evidence was re-read, not re-queried. No new user mapping decision is needed. Current classification
drift is still present; previously prepared dimension correction has not been deployed.

Authentication and warehouse metadata access succeeded through gcloud/bq; no direct BigQuery MCP
tool is exposed in this session, so the CLI is used. Reference tools were considered; built-in
filesystem/shell/web tools fit these reads. No credentials or customer records were read.

The First Principles method separated stable IDs, display attributes and source partition keys;
the [official framework](https://untools.co/first-principles/) was retrieved on 2026-11-02.
Technical checks followed the official
[ROUTINES metadata reference](https://docs.cloud.google.com/bigquery/docs/information-schema-routines)
and [table-function documentation](https://docs.cloud.google.com/bigquery/docs/table-functions):
regional inventory matches dataset location, and added dimension references need compatible access.
Two independent read-only agents checked sales and inventory/dependency scope. No implementation
or BigQuery function changes occurred in this Plan stage.

## Previous predicate/dimension plan and results (retained history)

## Historical Plan validation outcome

Planning artifacts and read-only discovery completed. Required repository checks fail on existing
baseline defects, so this Plan attempt is reported **failed**, not passed:

- `python3 scripts/validate_repo.py`: exit 1, three missing monitoring query links in
  `docs/warehouse-operations-dashboard.md`.
- `python3 -m unittest discover -s tests`: exit 1, 16 tests, four failures, one skipped.
  Failures: the same links; hash mismatch for snapshot `raw_product_variations.sql`; an unexpected
  `.DS_Store` within the snapshot; curated `fn_dim_sku.sql` differing from its observed snapshot.
- The affected tracked files equal their HEAD bytes, and the three linked query files are absent
  from HEAD as well as the working tree. These defects predate this Plan's three new Markdown files.
- Planning artifact structure and whitespace checks pass. `git diff --check` passes. Read-only
  cloud checks succeeded. No dbt commands or implementation tests were run in this stage.

Baseline repair is required before a clean implementation handoff. It must preserve snapshot
provenance and existing work; it is not performed during this Plan-only stage. Do not mark an
overall stage passed by excluding the known failures or rewriting hashes without investigating.

## Evidence and current state

Read-only discovery on 2026-11-02 used the active gcloud identity for the intended project.
Dataset discovery found 22 accessible datasets in `asia-southeast1`. Regional routine discovery
retrieved 47 name-mentioning routine bodies, including 41 table functions; review isolated twelve
active name-filtered functions. `core_warehouse` currently has 19 rows and 19 unique IDs. The
producer nevertheless permits duplicates after a rename because its DISTINCT includes names.

Warehouse-only history for the last 120 days returned 30 ID/name versions. Its dry run estimated
109,966,870 bytes; the subsequent SELECT succeeded under a 1 GB maximum. No order/customer
records were selected. Current live names show rename-induced classification drift: the Thai office
and EmSphere store became VIETNAM, marketing stock became P, and 480F became P.

Private discovery artifacts are in this thread's storage directory `warehouse-id-plan/`:

| Artifact | SHA-256 |
| --- | --- |
| `current-warehouses.json` | `9e6ef4d45541693548cb47c90da80b5299b90a980c1666d07a5f8f5524d38f89` |
| `live-warehouse-routines.json` | `1d19f4ea6909e4916429ff9dbdae448188ed446bc2abc8958b8daaa2350faac2` |
| `warehouse-name-history.json` | `b1130cd38df29e0877782c2d54fa7de6189faeedcf63367b95dbe12fda6561bb` |

Artifacts are investigation input, not a public export or safe-to-commit assertion. Review copied
routine comments for embedded identifiers before adding maintained source. Preserve unrelated live SQL.
Warehouse repo baseline: `8b4d858a70a589b0ff0fc5856b1c2c0bf3934855`, clean `main` before planning.
dbt baseline: `22bf41ad43849f76665d945bf727e2e970eff5a4`, `main`, pre-existing modified `logs/dbt.log`.
BB project `proj_3598auxu2c` resolves to sibling `lsoul_dbt`; current thread remains in warehouse repo.

## Verified warehouse policy

Map aliases through ID, never through similarity or accent stripping. This table is planned policy,
not a query result copied wholesale. Filter memberships are specified separately in SPEC.md.
The country/type values restore recognized pre-rename rules, with the head-office exception below.

| ID | Historical alias / current label | Country | Type |
| --- | --- | --- | --- |
| `115e6258-72f0-468a-9743-731d06a771fa` | Kho Offfice Thailand → TH – Office Stock | THAILAND | M |
| `133983a4-ff7d-4861-805c-0a1bdd51795f` | Kho Central World (current dimension) | THAILAND | P |
| `1a21d42d-d648-4fdd-9095-932fceb08a2d` | Kho hàng lỗi → VN – Defective Stock | VIETNAM | NONE |
| `28fc9c4c-6ad6-4dd3-8dda-bc44397c9e0f` | Kho Tổng 480F → VN – Central Warehouse (480F) | VIETNAM | B |
| `3c86e018-936a-4f33-8dda-7a0ad4f038db` | Kho Nguyễn Trãi (Back-up) → VN – Nguyễn Trãi Backup | VIETNAM | B |
| `3fb24787-3208-4fb7-9580-24a3754e51d6` | Kho Ecommerce Việt Nam → VN – E-commerce Stock | VIETNAM | P |
| `490ded40-64ba-4424-aaed-399abbf13fbb` | Central Ladprao (current dimension) | THAILAND | P |
| `4a93fada-d892-4bbd-8547-ec505e6104df` | Kho Nguyễn Trãi → VN – Nguyễn Trãi Store | VIETNAM | P |
| `66184c11-4f37-465b-b5a7-09cb026b9ebd` | Kho Marketing → VN – Marketing Stock | VIETNAM | M |
| `76be7836-6dc5-4b1c-9e48-b18e43127453` | Kho Trung Quốc (Back-up) → CN – Backup Stock (VN) | CHINA | B |
| `878504e9-fb75-4870-8504-b2ecdbc097ba` | Kho Thái (Back-up) → TH – Backup Stock (VN) | THAILAND | B |
| `ad07f1c9-84be-4c4d-bc5b-4de980ffb97e` | Kho Emsphere → TH – EmSphere Store | THAILAND | P |
| `c8b7a738-7b1c-4599-ad32-64d145b005c1` | LSOUL HEAD OFFICE → MKT HEAD OFFICE → VN – Marketing HO Stock | VIETNAM | P |
| `c9aea4ce-e71e-404e-b7c1-8d6ff342d748` | POP-UP OFFICE | VIETNAM | P |
| `cf854971-c137-4e23-86ec-4bd8fbed6990` | Kho Online → VN – Online Stock | VIETNAM | P |
| `d65e391f-711e-4f9d-81a4-ee54c2d7eca8` | Kho Whole Sale → VN – Wholesale Stock | VIETNAM | P |
| `e8d36467-0811-4020-a732-7e6564b5edb4` | Kho Whole Sale NT | VIETNAM | P |
| `eb66793a-2953-44da-8585-da8888111d6d` | LJIN (current dimension) | VIETNAM | B |
| `f0eb59ac-aa0e-4cf6-971e-01456e5dc3d2` | Kho MKT Thailand | THAILAND | P |

Head-office names imply inconsistent old CASE outcomes (NONE, then P); retain the latest existing P.
Do not guess M from its new label. For the two overseas backup labels ending `(VN)`, preserve the
old reporting country. These are explicit compatibility choices, not new geographic claims.

## Design and dependencies

`fresh live source + verified policy → source provenance → four function family slices + dimension → dbt → validation → review/readiness`

1. Capture and compare the twelve functions and warehouse procedure immediately before edits.
   Work from live bodies: the November 2 VN store UUID/name mismatch and October 29 removal of
   logging are absent from the October 28 snapshot. Retain existing source filenames and add nine
   exact-object files; do not deploy archived copies.
2. Keep `sql/live/` immutable. Add an explicit pending-source manifest outside it, recording source
   path, object, captured baseline hash, proposed hash and reason/status. Extend snapshot parity tests
   to validate this manifest for intentional divergence; unaffected files still require exact parity.
   Never replace snapshot hashes with hashes of SQL that has not been observed live.
3. Record the nineteen-ID classification policy as versioned configuration with provenance. Prefer
   inline values/CASEs generated or checked against that policy, avoiding a new production lookup
   table and new runtime permissions. Use a corresponding dbt macro/literal map and cross-check its
   contents offline; dbt must not depend on sibling files at execution time or live core tables.
4. Refactor the procedure to stage one deterministic row per ID and MERGE atomically. Use latest
   load/event ordering with a documented final tie-breaker; preserve a useful existing display name
   when incoming names are null. Validate target uniqueness before applying; current data is unique.
   If duplicates appear later, prepare a reviewed non-destructive repair path instead of blindly
   running MERGE. Correct known country/type values on all existing IDs, including absent-today IDs.
   Keep stale-source handling, activity cutoff, inserted_at behavior and the current no-log behavior.
5. Apply the same country/type policy to dbt's already deterministic model. Retain its eight columns,
   dbt-only destinations, watermark and source windows. Simplify activity grouping to ID. Document
   intentional timestamp differences rather than quietly forcing identical historical rebuild dates.
6. Rebuild lineage from truthful inputs: the existing generator consumes the observed snapshot and
   dbt manifest. Pending function changes should remain documented as pending; do not pass planned
   DDL as an observed snapshot just to make lineage look current.

The four function families can be implemented independently after the policy/source manifest is
settled. Procedure and dbt work can then proceed in parallel with separate file ownership. Snapshot
test/manifest changes and final validation must have one owner.

## Verification and checkpoints

Run focused regression coverage after each family/dimension slice, then the complete commands in
SPEC.md. Query-body dry runs and aggregate comparisons are optional additional live verification,
using bounded SELECTs only. A successful CREATE PROCEDURE dry run does not prove its DML semantics.
Test the extracted proposed SELECT/MERGE source with synthetic fixtures without mutating production.
No production or dbt build is part of this flow.

Compare identifiers/counts/totals before and after the rename for selected aggregate windows if useful;
expect recovered renamed rows and corrected dimension classifications. Avoid blindly asserting parity
with the currently broken VN store v2 predicate. Verify join multiplicity remains one dimension row per
ID. Preserve all date, money and unrelated source/status filters even if another bug is noticed.

## Risks and mitigation

| Risk | Mitigation |
| --- | --- |
| Stale snapshot overwrites current fixes | Live body/hash comparison, retain unrelated edits, block readiness if baseline changed |
| Country/type drift affects stock reports beyond direct filters | Verified nineteen-ID policy, old/new-name fixtures and consumer aggregate checks |
| Header vs item warehouse alters membership | Keep `o.warehouse_id`, include disagreement fixture |
| New warehouse or reused name | Never select by display name; audit unmapped IDs, preserve documented constant defaults |
| Duplicate sources multiply inventory | Deterministic dimension source, ID uniqueness precondition, join cardinality check |
| Snapshot hashes become misleading | Separate observed snapshot from proposed source manifest; retain strong integrity tests |
| dbt touches live datasets or existing log changes | Retain schema guard; offline commands with distinct log output |
| Procedure/table mutation causes partial change | Prepared transaction/preflight/rollback instructions; no execution in this flow |

## Future application and rollback (not executed)

Before any later authorized application, recapture exact live DDL, compare with reviewed baselines,
save a warehouse-table backup with an explicit unique destination, and recheck uniqueness/mappings.
Deploy the dimension procedure and validated dimension repair in dependency order, then functions;
verify the current table data as well as the procedure body. Apply dbt separately to `dbt_*` only.
Restore exact captured routine DDL and the backed-up dimension if acceptance fails. The captured VN
store v2 baseline already has a defect, so any emergency rollback must explicitly acknowledge that
restoring it reintroduces the known issue. Keep backups until post-change validation completes.

## Source and method record

- Canonical Holistics guidance and both Agent Flow bound skills freshly read; project schema and
  validation skills applied. Independent read-only SQL/dbt investigations completed.
- [First Principles](https://untools.co/first-principles/), retrieved 2026-11-02: establish identity,
  display attributes, grain and business classification separately. Domain conclusions came from
  repository and BigQuery evidence, not the framework.
- [BigQuery ROUTINES reference](https://docs.cloud.google.com/bigquery/docs/information-schema-routines),
  retrieved 2026-11-02: region-scoped routine definitions, DDL and last-altered metadata.
- BigQuery MCP tools were not exposed; supported `bq`/gcloud CLI was used. Reference MCP tools were
  considered; built-in filesystem/git/web tools were more direct. Prompt optimisation was manual;
  the optimiser status reported inactive/unavailable, and no optimiser engine was claimed.
