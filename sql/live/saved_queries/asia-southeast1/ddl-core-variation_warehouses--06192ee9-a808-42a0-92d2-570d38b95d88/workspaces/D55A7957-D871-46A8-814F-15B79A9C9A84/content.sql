--DROP TABLE `marine-cycle-484213-b4.core_pancake.core_variation_warehouses`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_pancake.core_variation_warehouses`
PARTITION BY DATE(updated_at)
CLUSTER BY variation_id, product_id,updated_at
AS
SELECT
  MAX(updated_at) AS updated_at,
  inserted_at,
  product_id, 
  product_tags,
  variation_id,
  warehouse_id,
  actual_remain_qty, 
  pending_qty, 
  remain_qty, 
  returning_qty, 
  total_qty, 
  waiting_qty
  FROM `marine-cycle-484213-b4.stg_pancake.stg_variation_warehouses`
  WHERE proc_date > '2024-05-19'
  GROUP BY
  inserted_at, 
  product_id, 
  product_tags,
  variation_id,
  warehouse_id,
  actual_remain_qty, 
  pending_qty, 
  remain_qty, 
  returning_qty, 
  total_qty, 
  waiting_qty