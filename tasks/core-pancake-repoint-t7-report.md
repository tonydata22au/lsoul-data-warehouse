# T7 and Phase 2 findings: core_pancake → core repoint (read-only, 2026-11-06)

Run in @thread:thr_fzwqdp2wyw. Everything here comes from read-only SELECTs, dry runs and Cloud metadata/log reads,
with aggregates and counts only. Nothing was deployed, created or written in BigQuery. Plan:
[core-pancake-repoint-plan.md](core-pancake-repoint-plan.md#phase-2-plan-2026-11-06-threadthr_fzwqdp2wyw).

## How the comparison was run

- **Same Vietnam day, same run:** old and new were measured side by side on 2026-11-06 (16:2x ICT), so the
  2026-11-05 baseline's date dependence doesn't matter. Its call set (thr_9b2q2q7sia `metrics.py`) was reused,
  plus `fn_order_product_inventory_summary`. 147 calls in total.
- **Old** = the live function as deployed (reads `core_pancake.core_*`).
- **New** = the repo file's body run as an ad-hoc SELECT (`scripts/compare_pancake_repoint.py`):
  - parameters bound as typed literals;
  - nested reportdb calls inlined from their repo files, so the whole new call tree is evaluated;
  - the two unbuilt dbt models replaced by **candidate subqueries** rendered offline from the local dbt code
    (`scripts/pancake_candidate_sql.py`): `core_pancake__variations` (with `images`) and `core_pancake__orders_returned`
    (history from the freeze SELECT). Their staging is inlined too, mapped to `raw_pancake`.
  - The other eight `core.core_pancake__*` tables are read as built: between the deployed commit 4f7c664 and the
    working tree, their dbt diff is only the `raw` dataset rename.
- **Metrics** (`metrics.py`, unchanged): row count; two order-independent hashes (BIT_XOR, and a sum mod p that keeps
  duplicates); per-column numeric sums, distinct counts and null counts. "Equal" means rows and both hashes are equal.
  Sums within 1e-6 relative count as float noise.
- Raw metrics: `$BB_THREAD_STORAGE/t7/{old,new,compare}.json` (thread storage, counts only).

### Candidate inputs checked against the old tables first

| Candidate | Rows | Check |
|---|---|---|
| core_pancake__variations | 4,467 = old 4,467 | `images` equal on 4,467 / 4,467 variations |
| core_pancake__orders_returned | 1,664 = old 1,664 | starts 2025-06-11; the 728 pre-cutover rows hash-equal the old table |
| core_pancake__product (as built) | 4,463 vs old 4,547 | 84 old-only products; 54 sale-end flags differ (see below) |

All three candidates dry-run. `fn_dim_sku` dry-runs only with the variations candidate: the built table has no
`images` yet.

## Results (147 calls)

| Status | Calls |
|---|---|
| equal (rows and both hashes) | 112 |
| equal within float tolerance | 7 (`fn_sale_ecom_china` ×2, `fn_sale_ecom_thai` ×1, `fn_thailand_product_inventory` ×4) |
| different, explained below | 19 |
| blocked (BigQuery planning limit on both sides) | 8 (`fn_product_inventory_summary` ×4, `fn_product_inventory_summary_v2` ×4) |
| old side fails live | 1 (`fn_order_product_inventory_summary`; new side measured alone) |

Every difference traces to `product` (sale-end flags, old-only products), `warehouse` (D2/D3) or the D8 change.
No call differs because of `orders_returned`, `order`, `order_item` or `customer`. That includes the D1 history:
with the candidate, the 728 rows that the built table lacks are back.

| Function | Calls | Result |
|---|---|---|
| fn_sale_* base, `_product`, `_v2` (29 functions) | 118 | 105 equal, 3 within tolerance, 10 different (rows 1 and 4 below) |
| fn_china_product_inventory | 4 | equal |
| fn_thailand_product_inventory | 4 | within tolerance |
| fn_stats_product_v2 | 3 | equal |
| fn_dim_sku | 1 | different (sale-end) |
| fn_product_variations_warehouse_summary | 6 | different (warehouse policy) |
| fn_product_inventory_overseas_shipment | 2 | different (D8 pending change) |
| fn_product_inventory_summary / _v2 | 8 | blocked |
| fn_order_product_inventory_summary | 1 | new only: 905,522 rows (old fails, T11) |

## Differences, attributed (Issue Trees: table input → which input changed → which rule)

| # | Calls | Old → new | Cause (evidence) | Verdict |
|---|---|---|---|---|
| 1 | `fn_dim_sku()` and `fn_sale_{ecom_china,ecom_taobao_tmall_manual_china,ecom_thai}_product` ×2 each | `is_sale_end` sum −54 (dim_sku 3,514 → 3,460), −2, −70, −60 | **Sale-end residue in the old table.** The 54 products flagged in old `core_pancake.core_product` but not in the new table share the same `display_id` and `raw_product_id`. None is in the current Dataform sale-end list, which equals the dbt seed (3,568 = 3,568, `sql/checks/check_pancake_sale_end_list_drift.sql` → `in_sync`). JOBS_BY_PROJECT shows these IDs were in the daily sale-end UPDATE only from 2026-06-18 to 2026-07-15. Every UPDATE since 2026-07-15 (116 runs to 2026-11-06) omits them, and the old procedure never resets `product_tags` on rows it doesn't reload. | Expected: new follows the current list. **Owner to confirm** the 2026-07-15 removal was intended (decision 2) |
| 2 | `fn_product_variations_warehouse_summary` ×6 | `''`: country distinct values 2 → 3, warehouse type 2 → 4. `'VIETNAM'`: rows 523,191 → 339,917, warehouses 16 → 12, stock 2,380,186 → 1,601,647 | **D2/D3 warehouse policy.** The new warehouse table classifies CN/TH-prefixed warehouses as CHINA/THAILAND and uses types B/M/NONE; the old table has them as VIETNAM/P (7 rows, `q-fix_core_pancake_warehouse_policy.sql`). The VIETNAM filter therefore drops 4 warehouses. | Expected (D2/D3) |
| 3 | `fn_product_inventory_overseas_shipment` ×2 | `warehouse_name` distinct values 4 → 2, rows equal | **D8 pending change:** the repo file joins canonical warehouse names, an undeployed change shipped with the repoint | Expected (D8) |
| 4 | `fn_sale_online_vn` ×2; `fn_sale_online_vn_v2(*, 3)` ×2 | total_products and total_units_sold −1; product_code distinct −1, nulls +1 | **Product rows missing from the new table:** 84 products exist only in the old table, and 6 of them have orders (rechecked today). In v2, one row loses its product_code: the product lookup misses. The single affected order item wasn't traced individually. | Expected (product data). Hypothesis consistent with evidence |
| 5 | `fn_sale_ecom_china_product` | `sum:retail_price` NaN on both sides | The comparison counted NaN ≠ NaN; fixed in review (`close_enough`). The real difference in these calls is row 1 | Not a difference |

The earlier table-level findings, rechecked today, explain why most functions are unaffected:

- `variation_warehouses`: total stock 89,215 old → 74,773 new. **New equals the latest raw load exactly**
  (0 mismatches over every (variation, warehouse) pair). Old differs from raw on 7,179 pairs and has 184 pairs (120 units)
  that raw doesn't have. Only `fn_product_inventory_summary(_v2)` read this table among the compared calls, and they're blocked.
- `order`: the same 79,531 order ids. The 5 differing orders differ only in customer snapshot columns
  (`customer_last_order_at`, `customer_updated_at`, `customer_purchased_amount` ×4, `customer_succeed_order_count`,
  `customer_currency` ×3, `customer_order_count` ×1), a load-timing effect. No compared function output changed.
- `product`: 84 old-only products (6 with orders); 54 sale-end flags (row 1).
- `orders_returned`: equal once the D1 history is included (candidate 1,664 = old 1,664).

## Blocked, with the exact unexecuted check

`fn_product_inventory_summary` and `fn_product_inventory_summary_v2` exceed BigQuery's query-planning limit as
ad-hoc metrics queries on **both** sides (old: the live function call; new: the inlined body). The 2026-11-05 baseline
hit the same limit for v2. Measuring them needs either the deployed new functions or a materialized intermediate in a
scratch dataset. Both are writes and outside this stage's authorization. After deploy (review packet, step 6):

```bash
uv run --project ../lsoul_dbt python scripts/compare_pancake_repoint.py "$OUT" fn_product_inventory_summary fn_product_inventory_summary_v2
```

Even then, the old `fn_product_inventory_summary` isn't repeatable: two identical runs gave different hashes on
2026-11-05. Compare it on row counts, key sets and sums with a tolerance. What *is* validated: both definitions dry-run
from the repo files, and v2's own body dry-runs with its parameters bound (nested calls on live definitions).

## Large routines (E): what was validated

| Routine | Definition (DDL dry run) | Body / branches |
|---|---|---|
| `fn_dim_sku` | Fails as is (`images` isn't built yet); **passes with the variations candidate** | Single statement, no parameters: the DDL dry run type-checks the whole body. Executed old vs new: differs only by sale-end (row 1) |
| `fn_product_inventory_summary_v2` | Passes | Single statement. `i_type` selects expressions, not statements, so the DDL dry run covers both modes. Execution blocked (above) |
| `sp_stock_inventory_dashboard_daily` | Passes, **but a procedure DDL dry run validates syntax only**: it passed with the nonexistent `raw.raw_order`. A script dry run validates only the first statement (probe: a missing table in statement 3 passed) | Converted to read-only queries (DECLAREs inlined, temp tables as CTEs, `raw.` → `raw_pancake.`). **All 21 statements dry-run:** 18 temp tables, the final `CREATE OR REPLACE TABLE … AS SELECT` body, and both result SELECTs, with `v_full_year_mode` TRUE (scheduled mode). The test-range branch (`v_full_year_mode` FALSE) differs only in DECLARE defaults and ASSERTs, which weren't evaluated. Never executed |

`sp_stock_inventory_dashboard_daily` as committed in the repo reads `raw.raw_order` and `raw.raw_product_variations`.
**It can't be deployed before the `raw` dataset exists** (raw-dataset migration). Apart from those two `raw.` lines and
three `core.core_pancake__*` repoints, it is identical to live (live last altered 2026-11-04 02:53Z, so live's 2026-11-04
change is preserved).

## Other Phase 2 findings

- **Sale-end seed (prompt item 5):** not stale. The live Dataform compilation used by the 2026-11-06 07:45 run
  (`compilationResults/5077a6ba…`, compiled 2026-11-04 00:09Z) lists 3,568 distinct IDs, identical to
  `pancake_sale_end_display_ids.csv`. No seed change was made. Future drift: `sql/checks/check_pancake_sale_end_list_drift.sql`
  (latest live UPDATE job vs `dbt_seeds`; `in_sync` today).
- **fn_order_product_inventory_summary (item 6), T11:** the meaning is established from JOBS history.
  - The call `(1, '')` was written on 2026-06-10, against `fn_china_product_inventory(i_number_year_back INT64, i_warehouse STRING)`:
    1 year back, `''` = store and ecommerce, rows per Kho (unaggregated).
  - On 2026-06-26 the callee changed to `(i_type INT64 — 0 grouped by variation, 1 per-Kho detail, i_number_year_back INT64)`.
    That has broken the caller ever since. Nothing has called it since 2026-06-10.
  - The same meaning under the new signature is `(1, 1)`. Fixed in the repo with that rationale.
  - Regression test: `tests/test_table_function_call_args.py`. It checks literal arguments against signatures for every
    reportdb TVF call; red before the fix, green after.
  - The fixed DDL dry-runs, and the new body runs: 905,522 rows.
  - `i_type 0` would aggregate store + ecommerce into one row per variation/warehouse/day: a behaviour change, not chosen.
- **raw_orders_returned:** has an active daily loader (trigger `pancake-insert-raw_orders_returned` 07:00 ICT → service
  `pancake-orders-returned`; ~110 rows a day). The service was deployed from source on 2026-03-01, and no repo folder
  matches its name. The dbt source note ("loaded only by the local script") and the earlier docs are out of date;
  not changed here (dbt file owned by the raw-dataset work).
- **raw_product_variations had no 2026-11-06 partition:** the loader ran at 07:05 and fetched 0 variations. dbt
  freshness warned. product, variations and variation_warehouses had no eligible changes today.
- **Time travel anomaly:** see the runbook's known limits. It doesn't affect any conclusion above.

## Readiness (T7 view)

- Candidate logic for the 10 tables plus all repointed readers: 119 of 147 calls equal or within float tolerance; 19 different,
  all attributed; 8 blocked by BigQuery planning limits; 1 failing only on the old side.
- Remaining owner decisions: the sale-end residue (row 1) and the warehouse policy effects (already decided, D2/D3).
