CREATE TABLE `marine-cycle-484213-b4.core_pancake.core_order_item`
(
  order_item_id STRING,
  order_date DATETIME,
  updated_at STRING,
  order_id STRING,
  system_id INT64,
  product_id STRING,
  product_name STRING,
  variation_id STRING,
  cart_quantity INT64,
  is_discount_percent INT64,
  unit_discount FLOAT64,
  item_total_discount INT64,
  line_total FLOAT64,
  retail_price FLOAT64,
  sales_revenue FLOAT64,
  original_retail_price FLOAT64,
  last_import_price FLOAT64,
  average_price FLOAT64,
  quantity_ordered INT64,
  quantity_returned INT64,
  quantity_returning INT64,
  return_count INT64,
  exchange_count INT64,
  is_wholesale INT64,
  is_one_time_product INT64,
  warehouse_id STRING,
  warehouse_name STRING
)
PARTITION BY DATE(order_date)
CLUSTER BY order_id, product_id, variation_id;
