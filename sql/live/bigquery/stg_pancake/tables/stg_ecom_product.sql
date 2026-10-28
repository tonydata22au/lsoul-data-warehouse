CREATE TABLE `marine-cycle-484213-b4.stg_pancake.stg_ecom_product`
(
  proc_date TIMESTAMP,
  ecom_product_id STRING,
  marketplace_id INT64,
  marketplace_shop_name STRING,
  ecom_title STRING,
  ecom_product_sku STRING,
  warehouse STRING,
  variations_id STRING,
  variations_linked_product_custom_id STRING,
  variations_linked_variation_custom_id STRING,
  variations_linked_variation_fields STRING,
  variations_linked_variation_price FLOAT64,
  variations_name STRING,
  variations_price FLOAT64,
  variations_quantity INT64,
  variations_sku STRING
)
PARTITION BY DATE(proc_date)
CLUSTER BY marketplace_id, ecom_product_sku, warehouse, variations_sku
OPTIONS(
  require_partition_filter=true
);
