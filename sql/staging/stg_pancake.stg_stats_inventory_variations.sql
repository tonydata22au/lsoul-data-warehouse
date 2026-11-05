--DROP TABLE  `marine-cycle-484213-b4.stg_pancake.stg_stats_inventory_variations`  --Each proc_date is the snapshot of the current stock qty, do not sum by date
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.stg_pancake.stg_stats_inventory_variations`
PARTITION BY DATE(proc_date)
AS
SELECT
  TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
  stat_id,
  variation_product_id AS product_id, 
  variation_product_custom_id AS product_custom_id, 
  variation_product_display_id AS product_display_id,
  variation_product_name AS product_name, 
  variation_id, 
  variation_custom_id, 
  variation_display_id, 
  variation_fields, 
  variation_product_inserted_at AS product_inserted_at, 
  SAFE_CAST(begin_inventory AS FLOAT64) begin_inventory, 
  SAFE_CAST(begin_inventory_value AS FLOAT64) begin_inventory_value, 
  SAFE_CAST(end_inventory AS FLOAT64) AS end_inventory, 
  SAFE_CAST(end_inventory_value AS FLOAT64) AS end_inventory_value, 
  SAFE_CAST(purchase_import AS FLOAT64) purchase_import, 
  SAFE_CAST(return_import AS FLOAT64) return_import, 
  SAFE_CAST(stocktaking_import AS FLOAT64) stocktaking_import, 
  SAFE_CAST(transfer_import AS FLOAT64) transfer_import, 
  SAFE_CAST(total_import AS FLOAT64) total_import, 
  SAFE_CAST(total_import_value AS FLOAT64) total_import_value, 
  SAFE_CAST(purchase_export AS FLOAT64) purchase_export , 
  SAFE_CAST(transfer_export AS FLOAT64) transfer_export, 
  SAFE_CAST(sell_export AS FLOAT64) sell_export, 
  SAFE_CAST(stocktaking_export AS FLOAT64) stocktaking_export, 
  SAFE_CAST(total_export AS FLOAT64) total_export, 
  SAFE_CAST(total_export_value AS FLOAT64) total_export_value
FROM `marine-cycle-484213-b4.raw_pancake.raw_stats_inventory_variations`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-01-01")