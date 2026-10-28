CREATE TABLE `marine-cycle-484213-b4.raw_pancake.raw_variations`
(
  inserted_at STRING,
  updated_at STRING,
  variation_id STRING,
  display_id STRING,
  fields STRING,
  is_hidden STRING,
  is_locked STRING,
  is_sell_negative_variation STRING,
  last_imported_price STRING,
  price_at_counter STRING,
  product_id STRING,
  remain_quantity STRING,
  retail_price STRING,
  variation_product_display_id STRING,
  variation_product_inserted_at STRING,
  variation_product_name STRING,
  variation_product_attributes STRING,
  variation_product_supplier_product_ids STRING,
  variation_product_tags STRING,
  variations_warehouses_actual_remain_quantity STRING,
  variations_warehouses_pending_quantity STRING,
  variations_warehouses_remain_quantity STRING,
  variations_warehouses_returning_quantity STRING,
  variations_warehouses_total_quantity STRING,
  variations_warehouses_waiting_quantity STRING,
  variations_warehouses_warehouse_id STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
