CREATE TABLE `marine-cycle-484213-b4.raw_pancake.raw_stats_product`
(
  stats_product_id STRING,
  begin_inventory STRING,
  begin_inventory_value STRING,
  end_inventory STRING,
  end_inventory_value STRING,
  product_id STRING,
  product_name STRING,
  product_inserted_at STRING,
  product_custom_id STRING,
  product_display_id STRING,
  product_images STRING,
  purchase_import STRING,
  return_import STRING,
  stocktaking_import STRING,
  transfer_import STRING,
  total_import STRING,
  total_import_value STRING,
  purchase_export STRING,
  transfer_export STRING,
  sell_export STRING,
  stocktaking_export STRING,
  total_export STRING,
  total_export_value STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
