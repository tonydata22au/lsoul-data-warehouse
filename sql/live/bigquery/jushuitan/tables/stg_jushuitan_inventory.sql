CREATE TABLE `marine-cycle-484213-b4.jushuitan.stg_jushuitan_inventory`
(
  proc_date TIMESTAMP,
  modified DATETIME,
  vn_modified DATETIME,
  ts BIGNUMERIC,
  item_id STRING,
  sku_id STRING,
  name STRING,
  qty NUMERIC,
  in_qty NUMERIC,
  return_qty NUMERIC,
  order_lock NUMERIC,
  pick_lock NUMERIC,
  defective_qty NUMERIC,
  purchase_qty NUMERIC,
  min_qty NUMERIC,
  max_qty NUMERIC,
  allocate_qty NUMERIC,
  virtual_qty NUMERIC
)
PARTITION BY DATE(proc_date);
