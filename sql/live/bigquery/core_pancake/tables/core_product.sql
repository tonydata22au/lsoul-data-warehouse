CREATE TABLE `marine-cycle-484213-b4.core_pancake.core_product`
(
  inserted_at DATETIME,
  updated_at DATETIME,
  raw_product_id STRING,
  display_id STRING,
  product_code STRING,
  product_name STRING,
  product_launch_date DATE,
  product_attributes STRING,
  supplier_product_ids STRING,
  product_tags STRING
)
PARTITION BY DATE(updated_at)
CLUSTER BY raw_product_id, display_id, product_name;
