CREATE TABLE `marine-cycle-484213-b4.surfosm.stg_surfosm_inventory`
(
  proc_date TIMESTAMP,
  parameter_date DATE,
  sku STRING,
  barcode STRING,
  product_name STRING,
  warehouse_name STRING,
  warehouse_code STRING,
  stock_on_hand INT64,
  stock_normal INT64,
  stock_defect INT64,
  stock_quarantine INT64,
  stock_expired INT64,
  stock_shelf_life_hold INT64,
  stock_pending_destruction INT64
)
PARTITION BY DATE(proc_date);
