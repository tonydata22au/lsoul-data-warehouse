CREATE TABLE `marine-cycle-484213-b4.dianplus.stg_dianplus_inventory`
(
  proc_date TIMESTAMP,
  inserted_at DATE,
  brandId INT64,
  warehouse_name STRING,
  spuId INT64,
  spuCode STRING,
  skuId INT64,
  skuCode STRING,
  realNum INT64,
  lockNum INT64,
  canUseNum INT64,
  frozenNum INT64,
  transitNum INT64,
  defectNum INT64
)
PARTITION BY DATE(proc_date);
