CREATE TABLE `marine-cycle-484213-b4.stg_pancake.stg_product`
(
  proc_date TIMESTAMP,
  inserted_at DATETIME,
  updated_at DATETIME,
  product_id STRING,
  display_id STRING,
  product_name STRING,
  product_attributes STRING,
  supplier_product_ids STRING,
  product_tags STRING
)
PARTITION BY DATE(proc_date);
