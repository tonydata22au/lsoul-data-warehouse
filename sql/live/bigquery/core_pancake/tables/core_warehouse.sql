CREATE TABLE `marine-cycle-484213-b4.core_pancake.core_warehouse`
(
  warehouse_id STRING,
  warehouse_code STRING,
  warehouse_name STRING,
  country STRING,
  warehouse_type STRING,
  is_active INT64,
  inserted_at DATETIME,
  updated_at DATETIME
)
CLUSTER BY warehouse_id, warehouse_name;
