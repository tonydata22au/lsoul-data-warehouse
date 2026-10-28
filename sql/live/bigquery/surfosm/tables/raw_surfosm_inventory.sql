CREATE TABLE `marine-cycle-484213-b4.surfosm.raw_surfosm_inventory`
(
  as_of_date STRING,
  sku STRING,
  barcode STRING,
  product_name STRING,
  warehouse_name STRING,
  warehouse_code STRING,
  stock_on_hand STRING,
  stock_normal STRING,
  stock_defect STRING,
  stock_quarantine STRING,
  stock_expired STRING,
  stock_shelf_life_hold STRING,
  stock_pending_destruction STRING,
  updated_at STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
