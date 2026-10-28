CREATE TABLE `marine-cycle-484213-b4.stg_pancake.stg_variation_warehouses`
(
  proc_date TIMESTAMP,
  inserted_at DATETIME,
  updated_at DATETIME,
  product_id STRING,
  product_tags STRING,
  variation_id STRING,
  warehouse_id STRING,
  actual_remain_qty FLOAT64,
  pending_qty INT64,
  remain_qty INT64,
  total_qty INT64,
  returning_qty INT64,
  waiting_qty INT64
)
PARTITION BY DATE(proc_date);
