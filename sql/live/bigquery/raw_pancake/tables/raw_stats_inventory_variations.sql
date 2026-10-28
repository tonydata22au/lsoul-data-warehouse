CREATE TABLE `marine-cycle-484213-b4.raw_pancake.raw_stats_inventory_variations`
(
  stat_id STRING,
  variation_id STRING,
  variation_custom_id STRING,
  variation_display_id STRING,
  variation_fields STRING,
  variation_product_id STRING,
  variation_product_custom_id STRING,
  variation_product_display_id STRING,
  variation_product_inserted_at STRING,
  variation_product_name STRING,
  begin_inventory STRING,
  begin_inventory_value STRING,
  end_inventory STRING,
  end_inventory_value STRING,
  purchase_export STRING,
  purchase_import STRING,
  return_import STRING,
  sell_export STRING,
  stocktaking_export STRING,
  stocktaking_import STRING,
  total_export STRING,
  total_export_value STRING,
  total_import STRING,
  total_import_value STRING,
  transfer_export STRING,
  transfer_import STRING,
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
