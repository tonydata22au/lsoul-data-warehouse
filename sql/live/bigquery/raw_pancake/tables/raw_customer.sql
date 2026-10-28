CREATE TABLE `marine-cycle-484213-b4.raw_pancake.raw_customer`
(
  entry_id STRING,
  inserted_at STRING,
  updated_at STRING,
  customer_id STRING,
  username STRING,
  tags STRING,
  fb_id STRING,
  is_block STRING,
  assigned_user_id STRING,
  creator_name STRING,
  creator_id STRING,
  currency STRING,
  order_count STRING,
  succeed_order_count STRING,
  returned_order_count STRING,
  purchased_amount STRING,
  last_order_at STRING,
  order_sources STRING,
  shop_customer_addresses_id STRING,
  shop_customer_addresses_country_code STRING,
  shop_customer_addresses_province_id STRING,
  shop_customer_addresses_commune_id STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
