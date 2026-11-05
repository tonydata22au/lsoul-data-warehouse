--drop table `marine-cycle-484213-b4.jushuitan.core_jushuitan_inventory`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.jushuitan.core_jushuitan_inventory`
PARTITION BY DATE(vn_modified)
CLUSTER BY item_id,sku_id,product_code
OPTIONS (
  require_partition_filter=false
) AS
SELECT
  proc_date,
  modified,
  vn_modified,
  ts, 
  REGEXP_EXTRACT(sku_id, r'^([^-]+)') AS product_code,
      DATE(
        SAFE_CAST(SUBSTR(REGEXP_EXTRACT(sku_id, r'\d{6}'), 1, 2) AS INT64) + 2000,
        SAFE_CAST(SUBSTR(REGEXP_EXTRACT(sku_id, r'\d{6}'), 3, 2) AS INT64),
        01
        ) product_launch_date, 
  item_id,
  sku_id, 
  name, 
  qty, 
  in_qty, 
  return_qty, 
  defective_qty,
  purchase_qty, 
  allocate_qty, 
  virtual_qty
  FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_inventory` 
  WHERE DATE(proc_date) = '2026-06-01'
  AND item_id is not null AND UPPER(item_id) NOT LIKE '%TEST%';