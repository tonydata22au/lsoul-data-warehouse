--drop table `marine-cycle-484213-b4.jushuitan.stg_jushuitan_inventory`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.jushuitan.stg_jushuitan_inventory`
PARTITION BY DATE(proc_date)
OPTIONS (
  require_partition_filter=false
) AS
SELECT
  TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', modified))  AS modified,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', vn_modified))  AS vn_modified,
  SAFE_CAST(ts AS BIGNUMERIC) AS ts,
  item_id,
  sku_id, 
  name, 
  SAFE_CAST(qty AS NUMERIC) AS qty,
  SAFE_CAST(in_qty AS NUMERIC) AS in_qty,
  SAFE_CAST(return_qty AS NUMERIC) AS return_qty,
  SAFE_CAST(order_lock AS NUMERIC) AS order_lock,
  SAFE_CAST(pick_lock AS NUMERIC) AS pick_lock,
  SAFE_CAST(defective_qty AS NUMERIC) AS defective_qty,
  SAFE_CAST(purchase_qty AS NUMERIC) AS purchase_qty,
  SAFE_CAST(min_qty AS NUMERIC) AS min_qty,
  SAFE_CAST(max_qty AS NUMERIC) AS max_qty,
  SAFE_CAST(allocate_qty AS NUMERIC) AS allocate_qty,
  SAFE_CAST(virtual_qty AS NUMERIC) AS virtual_qty

FROM `marine-cycle-484213-b4.jushuitan.raw_jushuitan_inventory` 
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) = TIMESTAMP("2026-06-01")

