CREATE TABLE `marine-cycle-484213-b4.stg_pancake.stg_warehouse_transfers_completed`
(
  proc_date TIMESTAMP,
  inserted_at DATETIME,
  warehouse_transfer_id STRING,
  warehouse_transfer_display_id STRING,
  status INT64,
  updated_status_at STRING,
  from_warehouse_id STRING,
  from_warehouse_name STRING,
  to_warehouse_id STRING,
  to_warehouse_name STRING,
  creator_name STRING,
  shipping_fee FLOAT64,
  total_quantity INT64,
  items_display_id STRING,
  items_id STRING,
  items_product_display_id STRING,
  items_product_name STRING,
  items_quantity INT64,
  items_variation_display_id STRING,
  items_variation_id STRING,
  items_variation_fields STRING,
  items_variation_images STRING,
  items_variation_inserted_at STRING,
  items_variation_is_hidden INT64,
  items_variation_is_locked INT64,
  items_variation_is_removed INT64,
  items_variation_is_sell_negative_variation INT64,
  items_variation_last_imported_price FLOAT64,
  items_variation_price_at_counter FLOAT64,
  items_variation_product_id STRING,
  items_variation_retail_price FLOAT64,
  items_variation_retail_price_after_discount FLOAT64,
  items_variation_wholesale_price FLOAT64,
  items_variation_product_display_id STRING,
  items_variation_product_inserted_at STRING,
  items_variation_product_name STRING,
  items_variation_product_attributes STRING,
  items_variation_product_supplier_product_ids STRING,
  items_variation_is_sell_negatisve_variation FLOAT64
)
PARTITION BY DATE(inserted_at)
CLUSTER BY warehouse_transfer_display_id, items_display_id, items_product_display_id
OPTIONS(
  require_partition_filter=true
);
