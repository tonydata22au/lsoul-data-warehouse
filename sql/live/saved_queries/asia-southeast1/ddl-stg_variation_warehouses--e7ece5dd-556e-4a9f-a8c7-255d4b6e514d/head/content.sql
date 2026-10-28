--Drop table `marine-cycle-484213-b4.stg_pancake.stg_variation_warehouses`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.stg_pancake.stg_variation_warehouses`
PARTITION BY DATE(proc_date)
AS
SELECT DISTINCT
  TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', inserted_at))  AS inserted_at,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', updated_at))  AS updated_at,
  product_id,
  product_tags,
  variation_id,
  variations_warehouses_warehouse_id AS warehouse_id,
  SAFE_CAST(variations_warehouses_actual_remain_quantity AS FLOAT64) AS actual_remain_qty,
  SAFE_CAST(variations_warehouses_pending_quantity AS INT64) AS pending_qty,
  SAFE_CAST(variations_warehouses_remain_quantity AS INT64) AS remain_qty,
  SAFE_CAST(variations_warehouses_total_quantity AS INT64) AS total_qty,
  SAFE_CAST(variations_warehouses_returning_quantity AS INT64) AS returning_qty,
  SAFE_CAST(variations_warehouses_waiting_quantity AS INT64) AS waiting_qty
FROM `marine-cycle-484213-b4.raw_pancake.raw_product_variations`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-01-01")