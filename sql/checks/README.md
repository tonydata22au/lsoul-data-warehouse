# sql/checks/

Placeholder for data-quality checks. Existing monitoring queries:
[`../ad_hoc/q-check_scheduler_status.sql`](../ad_hoc/q-check_scheduler_status.sql) (raw partition
freshness, despite its name) and [`../archive/zarchived-raw_pancake.sp_check_partition_insert_dates.sql`](../archive/zarchived-raw_pancake.sp_check_partition_insert_dates.sql) (archived 2026-11-05: never deployed).

Read-only checks (run with `bq query --use_legacy_sql=false --location=asia-southeast1 --maximum_bytes_billed=… < file`):

| File | Checks |
|---|---|
| [`check_warehouse_identity.sql`](check_warehouse_identity.sql) | `core.core_pancake__warehouse` against the warehouse policy |
| [`check_pancake_sale_end_list_drift.sql`](check_pancake_sale_end_list_drift.sql) | dbt sale-end seed (`dbt_seeds.pancake_sale_end_display_ids`) against the latest live Dataform sale-end UPDATE. Expect `in_sync` |
