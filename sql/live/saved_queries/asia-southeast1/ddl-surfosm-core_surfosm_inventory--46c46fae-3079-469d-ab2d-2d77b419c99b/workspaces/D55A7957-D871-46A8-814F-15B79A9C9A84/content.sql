--truncate table `marine-cycle-484213-b4.surfosm.core_surfosm_inventory`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.surfosm.core_surfosm_inventory`
PARTITION BY parameter_date
CLUSTER BY  sku, barcode
OPTIONS (
  require_partition_filter=false
) AS
SELECT
parameter_date,
sku, 
barcode, 
product_name, 
warehouse_name, 
warehouse_code,
stock_on_hand,
stock_normal, 
stock_defect, 
stock_quarantine, 
stock_expired, 
stock_shelf_life_hold, 
stock_pending_destruction
FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_inventory`
WHERE DATE(proc_date) >= '2026-07-17'