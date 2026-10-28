CREATE TABLE `marine-cycle-484213-b4.stg_pancake.stg_stats_product_increment_by_date`
(
  proc_date TIMESTAMP,
  inserted_at DATETIME,
  stats_id STRING,
  product_id STRING,
  product_custom_id STRING,
  product_display_id STRING,
  product_inserted_at DATETIME,
  product_name STRING,
  begin_inventory FLOAT64,
  begin_inventory_value FLOAT64,
  end_inventory FLOAT64,
  end_inventory_value FLOAT64,
  purchase_import FLOAT64,
  return_import FLOAT64,
  stocktaking_import FLOAT64,
  transfer_import FLOAT64,
  total_import FLOAT64,
  total_import_value FLOAT64,
  purchase_export FLOAT64,
  transfer_export FLOAT64,
  sell_export FLOAT64,
  stocktaking_export FLOAT64,
  total_export FLOAT64,
  total_export_value FLOAT64
)
PARTITION BY DATE(proc_date)
CLUSTER BY inserted_at, product_id, product_custom_id
OPTIONS(
  require_partition_filter=true
);
