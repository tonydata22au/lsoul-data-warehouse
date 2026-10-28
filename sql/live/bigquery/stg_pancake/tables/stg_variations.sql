CREATE TABLE `marine-cycle-484213-b4.stg_pancake.stg_variations`
(
  proc_date TIMESTAMP,
  inserted_at DATETIME,
  updated_at DATETIME,
  product_id STRING,
  variation_id STRING,
  variation_display_id STRING,
  size_name STRING,
  size_value STRING,
  color_name STRING,
  color_value STRING,
  retail_price FLOAT64,
  retail_price_after_discount FLOAT64,
  last_imported_price FLOAT64,
  total_purchase_price FLOAT64,
  price_at_counter FLOAT64,
  wholesale_price FLOAT64,
  remain_quantity INT64,
  is_hidden INT64,
  is_locked INT64,
  is_removed INT64,
  is_sell_negative INT64,
  is_composite INT64
)
PARTITION BY DATE(proc_date);
