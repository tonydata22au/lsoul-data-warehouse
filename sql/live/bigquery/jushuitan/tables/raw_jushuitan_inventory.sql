CREATE TABLE `marine-cycle-484213-b4.jushuitan.raw_jushuitan_inventory`
(
  ts STRING,
  modified STRING,
  vn_modified STRING,
  item_id STRING,
  sku_id STRING,
  name STRING,
  qty STRING,
  in_qty STRING,
  return_qty STRING,
  order_lock STRING,
  pick_lock STRING,
  defective_qty STRING,
  purchase_qty STRING,
  min_qty STRING,
  max_qty STRING,
  allocate_qty STRING,
  virtual_qty STRING,
  inserted_at STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
