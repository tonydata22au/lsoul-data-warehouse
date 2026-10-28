CREATE TABLE `marine-cycle-484213-b4.jushuitan.core_jushuitan_inventory`
(
  proc_date TIMESTAMP,
  modified DATETIME,
  vn_modified DATETIME,
  ts BIGNUMERIC,
  product_code STRING,
  product_launch_date DATE,
  item_id STRING,
  sku_id STRING,
  name STRING,
  qty NUMERIC,
  in_qty NUMERIC,
  return_qty NUMERIC,
  defective_qty NUMERIC,
  purchase_qty NUMERIC,
  allocate_qty NUMERIC,
  virtual_qty NUMERIC
)
PARTITION BY DATE(vn_modified)
CLUSTER BY item_id, sku_id, product_code;
