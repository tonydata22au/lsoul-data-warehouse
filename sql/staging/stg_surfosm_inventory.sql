--drop table `marine-cycle-484213-b4.surfosm.stg_surfosm_inventory`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.surfosm.stg_surfosm_inventory`
PARTITION BY DATE(proc_date)
AS
SELECT
TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
SAFE_CAST(as_of_date AS DATE) AS parameter_date,
sku, 
barcode, 
product_name, 
warehouse_name, 
warehouse_code,
SAFE_CAST(stock_on_hand AS INT64) AS stock_on_hand,
SAFE_CAST(stock_normal AS INT64) AS stock_normal, 
SAFE_CAST(stock_defect AS INT64) AS stock_defect, 
SAFE_CAST(stock_quarantine AS INT64) AS stock_quarantine, 
SAFE_CAST(stock_expired AS INT64) AS stock_expired, 
SAFE_CAST(stock_shelf_life_hold AS INT64) AS stock_shelf_life_hold, 
SAFE_CAST(stock_pending_destruction AS INT64) AS stock_pending_destruction
FROM `marine-cycle-484213-b4.surfosm.raw_surfosm_inventory`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) = '2026-07-17'