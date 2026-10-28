--drop table `marine-cycle-484213-b4.dianplus.core_dianplus_inventory`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.dianplus.core_dianplus_inventory`
PARTITION BY updated_at
CLUSTER BY  proc_date,skuId,skuCode
OPTIONS (
  require_partition_filter=false
) AS
SELECT
proc_date,
DATE(inserted_at) AS updated_at, 
brandId,
warehouse_name,
spuId, 
spuCode, 
skuId,
REGEXP_EXTRACT(skuCode, r'^([^-]+)') AS product_code,
   DATE(
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(skuCode, r'\d{6}'), 1, 2) AS INT64) + 2000,
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(skuCode, r'\d{6}'), 3, 2) AS INT64),
    01
    ) product_launch_date, 
skuCode, 
realNum, 
lockNum, 
canUseNum, 
frozenNum, 
transitNum, 
defectNum
FROM `marine-cycle-484213-b4.dianplus.stg_dianplus_inventory` 
WHERE DATE(proc_date) = "2026-06-02"