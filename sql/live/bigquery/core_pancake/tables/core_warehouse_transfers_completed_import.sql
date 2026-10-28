CREATE TABLE `marine-cycle-484213-b4.core_pancake.core_warehouse_transfers_completed_import`
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
  total_quantity INT64
)
PARTITION BY DATE(inserted_at)
CLUSTER BY warehouse_transfer_display_id, from_warehouse_id, to_warehouse_id
OPTIONS(
  require_partition_filter=true
);
