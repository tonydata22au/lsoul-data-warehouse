--truncate table `marine-cycle-484213-b4.core_pancake.core_inventory_histories`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_pancake.core_inventory_histories`
PARTITION BY DATE(inserted_at)
CLUSTER BY table_name, ref_display_id, warehouse_name,variation_id
AS
SELECT
    inserted_at,
    inventory_history_id,
    record_id,
    table_name,
    note_type,
    type,
    ref_display_id,
    warehouse_id,
    warehouse_name,
    quantity,
    remain_quantity,
    variation_inserted_at,
    variation_updated_at,
    variation_product_id AS product_id,
    REGEXP_EXTRACT(variation_display_id, r'^([^-]+)') AS product_code,
    DATE(
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(variation_display_id, r'\d{6}'), 1, 2) AS INT64) + 2000,
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(variation_display_id, r'\d{6}'), 3, 2) AS INT64),
    01
    ) product_launch_date,
    variation_id,
    variation_display_id,
    variation_name,
    variation_remain_quantity AS remain_qty,
    variation_total_quantity AS total_qty,
    variation_is_composite AS is_composite,
    variation_is_hidden AS is_hidden,
    variation_is_locked AS is_locked,
    variation_is_removed AS is_removed,
    variation_is_sell_negative_variation AS is_sell_negative_variation,
    avg_price,
    variation_last_imported_price AS last_imported_price,
    variation_price_at_counter AS price_counter,
    variation_retail_price AS retail_price,
    variation_retail_price_after_discount AS retail_price_after_discount,
    variation_wholesale_price AS wholesale_price,
    current_inventory_warehouse_id AS inv_warehouse_id,
    current_inventory_name AS inv_warehouse_name,
    current_inventory_actual_remain_quantity AS inv_actual_remain_qty,
    current_inventory_remain_quantity AS inv_remain_qty,
    current_inventory_total_quantity AS inv_total_qty
FROM `marine-cycle-484213-b4.stg_pancake.stg_inventory_histories`
WHERE  1=1
AND DATE(proc_date) = "2026-06-02";