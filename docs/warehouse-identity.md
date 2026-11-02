# Warehouse identity migration

Status: prior predicate/dimension work verified; canonical-name extension built and awaiting Verify/Review. No production application. See the
[verification report](../tasks/verify-report.md) for compilation, aggregate and temporary-table
execution evidence. Agent Flow's Review and Ship assess readiness; Ship does not deploy.

## Canonical-name continuation

The continuation from thread `thr_qjwbpax4cj` updates 37 function definitions: 29 sales leaves
and eight inventory/report functions. Five wrappers inherit canonical names; seven additional
aggregate consumers complete the 49-function regression scope. See the
[scope inventory](../tasks/warehouse-name-inventory.md) and [Build report](../tasks/warehouse-name-build-report.md).
The earlier verification and Ship reports below do not certify this extension.

Returned warehouse names now resolve from `core_pancake.core_warehouse` by the corresponding
returned ID. Existing order-header ID predicates remain header-based even when a row displays
an item warehouse. Wholesale base has no returned warehouse ID and uses its header ID.
Store/channel labels remain stable ID-based business labels. Unknown IDs preserve rows with NULL
names; modes that deliberately combine warehouses retain empty ID/name fields.

Fourteen overseas sales functions use scalar lookups for their existing constant reporting IDs;
all other direct targets use dimension joins or resolve names inherited from corrected leaves.
Dimension IDs must be unique: scalar lookups reject duplicate rows; joins would multiply rows.
Run the existing identity preflight before any later application and preserve the previously
prepared deterministic producer. Do not mask duplicate IDs with ANY_VALUE or LIMIT 1.

The historical source warehouse used to partition Dianplus stock deltas is explicitly named
`source_warehouse_name` internally. It remains a source calculation key, distinct from the
Pancake reporting ID and canonical output name. Inventory combined-source display labels are
replaced without changing their date-cutover or stock rules. Assortment aggregation retains
warehouse ID in its grouping so two IDs sharing a current name remain distinct.

The preexisting local `fn_product_inventory_summary_v2` draft contained unrelated columns and
logic absent from the live function. Its exact bytes are preserved in
[the SQL archive](../sql/archive/zarchived-fn_product_inventory_summary_v2-pre-canonical-20261102.sql).
The maintained function now starts from captured live DDL, preserving the live output interface.
The provenance validator checks the archived draft hash as well as maintained/snapshot hashes.

For later application, extend the original sequence below to the **37 reviewed functions** in
the continuation inventory. Exact captured rollback DDLs are stored privately in the current
thread's `warehouse-name-build/rollback/`, with a hash manifest. Recapture and reconcile any live
drift before applying. Do not deploy an archive, the snapshot directory, or every source-provenance
entry indiscriminately. Functions reading persisted reports now resolve names directly; this
extension does not require refreshing those report tables. Verify caller access to core_warehouse.

## Earlier predicate/dimension behavior and policy

Twelve reporting functions select warehouses using the order header's `warehouse_id`: base,
product and v2 variants of VN ecommerce, VN online, VN stores and Thai stores. Existing v2
filenames are retained; nine additional sources live in `sql/functions/warehouse_identity/`.
`sql/source_provenance.json` is the exact object/path index. Online source OR logic, financial
calculations, date windows and interfaces remain unchanged. Store labels use the same IDs.
Names and name-derived codes remain display attributes.

The warehouse procedure stages one latest useful name per ID and atomically upserts it. It
corrects country/type on existing IDs even when absent from today's load, retaining the activity
cutoff. Duplicate/blank target IDs block application; no data is silently deleted. The historic
June 2 CTAS is not an application step.

The [ID policy](../sql/config/warehouse_policy.json) covers nineteen verified IDs. Aliases are
evidence, not runtime predicates. Head-office remains VIETNAM/P because historical names imply
conflicting classifications. Overseas backup warehouses retain their reporting country despite
new labels ending `(VN)`. Unknown IDs retain constant VIETNAM/P defaults and require policy review.

The sibling `lsoul_dbt` uses a local policy macro with offline parity tests. It keeps its eight
columns, dbt-only datasets and load-window/timestamp conventions. Reports are not repointed.

## Verification

```sh
python3 scripts/validate_sql_sources.py
python3 scripts/validate_repo.py
python3 -m unittest discover -s tests
git diff --check
```

Regression tests execute extracted SQL on synthetic fixtures: renamed/copied names, null/unknown
IDs, header/item disagreement, duplicate inputs, tied timestamps and activity. SQLite tests do not
prove BigQuery transaction execution; the separate Verify stage also executed the procedure body
against synthetic BigQuery temporary tables. This does not establish scheduler or concurrency behavior.
The [read-only dimension check](../sql/checks/check_warehouse_identity.sql) reports duplicate,
blank or unknown IDs and classification mismatches; it does not repair data. Empty results cover
only those checks. Aggregate checks should exercise v2 modes 0, 1 and 3, verify join cardinality
and explain restored renamed rows. The broken original VN store v2 is not an equality baseline.

## Later application sequence (not executed)

1. Recapture live DDL and compare exact hashes with reviewed baselines. Save recoverable exact
   routine DDL and a uniquely named warehouse-table backup. Reconcile concurrent edits first.
   Plan/Build captures live privately under this thread's `warehouse-id-plan/` storage directory.
2. Run dimension preflight. Classification mismatches are expected before repair; duplicate/blank
   IDs or unreviewed mappings block the run. Review transaction and stale-source behavior.
3. Deploy only `sql/procedures/sp_pancake_core_warehouse_insert.sql`, then call that producer once
   in the intended project/region to apply the dimension correction. Verify actual table rows.
   Do not run schema scripts, the historic CTAS, snapshot directories or unrelated pipelines.
4. Deploy the twelve reviewed functions from the provenance index; verify interfaces, membership,
   channel labels and aggregates. Each maintained source uses CREATE OR REPLACE.
5. Apply dbt separately following its runbook and dataset guard, including classification post-hooks
   for IDs absent from the incremental batch.
6. Recapture affected definitions with truthful dates; resolve pending status only after readback.

## Rollback

Restore exact saved routine definitions and the warehouse-table backup if acceptance fails.
Routine rollback alone cannot undo dimension changes. Preserve raw/staging data and keep dbt
rollback separate. Restoring the captured VN store v2 definition reintroduces its known UUID-versus-
name defect; acknowledge that explicitly. Retain backups until acceptance. No rollback has run.
