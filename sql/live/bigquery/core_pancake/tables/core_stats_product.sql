CREATE TABLE `marine-cycle-484213-b4.core_pancake.core_stats_product`
(
  inserted_at TIMESTAMP,
  product_id STRING,
  product_code STRING,
  product_custom_id STRING,
  product_name STRING,
  total_import FLOAT64,
  total_export FLOAT64,
  total_import_value FLOAT64,
  total_export_value FLOAT64,
  product_display_id STRING,
  product_inserted_at DATETIME,
  begin_inventory FLOAT64,
  end_inventory FLOAT64,
  begin_inventory_value FLOAT64,
  end_inventory_value FLOAT64,
  purchase_import FLOAT64,
  return_import FLOAT64,
  stocktaking_import FLOAT64,
  transfer_import FLOAT64,
  purchase_export FLOAT64,
  transfer_export FLOAT64,
  sell_export FLOAT64,
  stocktaking_export FLOAT64
)
PARTITION BY DATE(inserted_at)
CLUSTER BY product_id, product_custom_id, product_display_id;
