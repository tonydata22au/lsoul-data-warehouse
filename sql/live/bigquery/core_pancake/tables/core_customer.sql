CREATE TABLE `marine-cycle-484213-b4.core_pancake.core_customer`
(
  inserted_at DATETIME,
  updated_at DATETIME,
  customer_id STRING,
  username STRING,
  tags STRING,
  fb_id STRING,
  is_block INT64,
  assigned_user_id STRING,
  creator_name STRING,
  creator_id STRING,
  currency STRING,
  order_count INT64,
  succeed_order_count INT64,
  returned_order_count INT64,
  purchased_amount FLOAT64,
  last_order_at DATETIME,
  order_sources INT64,
  shop_customer_addresses_id STRING,
  shop_customer_addresses_country_code STRING,
  shop_customer_addresses_province_id STRING,
  shop_customer_addresses_commune_id STRING
)
PARTITION BY DATE(updated_at)
CLUSTER BY customer_id, order_sources, last_order_at;
