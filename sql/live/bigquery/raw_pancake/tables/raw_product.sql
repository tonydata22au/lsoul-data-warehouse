CREATE TABLE `marine-cycle-484213-b4.raw_pancake.raw_product`
(
  inserted_at STRING,
  product_id STRING,
  product_name STRING,
  custom_id STRING,
  display_id STRING,
  image STRING,
  product_attributes STRING,
  supplier_product_ids STRING,
  tags STRING,
  type STRING,
  variation_average_imported_price STRING,
  variation_display_id STRING,
  variation_inserted_at STRING,
  variation_is_hidden STRING,
  variation_is_locked STRING,
  variation_is_removed STRING,
  variation_is_sell_negative STRING,
  variation_last_imported_price STRING,
  variation_price_at_counter STRING,
  variation_remain_quantity STRING,
  variation_retail_price STRING,
  variation_retail_price_after_discount STRING,
  variation_total_purchase_price STRING,
  variation_warehouse_actual_remain_quantity STRING,
  variation_warehouse_total_quantity STRING,
  variation_warehouse_id STRING,
  variation_warehouse_returning_quantity STRING,
  variation_warehouse_waiting_quantity STRING,
  updated_at STRING,
  wholesale_price STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
