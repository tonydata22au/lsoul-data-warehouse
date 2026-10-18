--DROP TABLE `marine-cycle-484213-b4.dianplus.stg_dianplus_inventory`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.dianplus.stg_dianplus_inventory`
PARTITION BY DATE(proc_date)
OPTIONS (
  require_partition_filter=false
) AS
SELECT
TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
DATE(DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', inserted_at)))  AS inserted_at,
SAFE_CAST(brandId AS INT64) AS brandId,
CASE WHEN storageId = '1214524817899254785' THEN 'LSOUL' END AS warehouse_name,
SAFE_CAST(spuId AS INT64) AS spuId, 
spuCode, 
SAFE_CAST(skuId AS INT64) AS skuId, 
skuCode, 
SAFE_CAST(realNum AS INT64) AS realNum, 
SAFE_CAST(lockNum AS INT64) AS lockNum, 
SAFE_CAST(canUseNum AS INT64) AS canUseNum, 
SAFE_CAST(frozenNum AS INT64) AS frozenNum, 
SAFE_CAST(transitNum AS INT64) AS transitNum, 
SAFE_CAST(defectNum AS INT64) AS defectNum 

FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_inventory` 
WHERE
TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-06-01")
AND  storageId = '1214524817899254785'