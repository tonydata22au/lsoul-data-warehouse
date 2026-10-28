CREATE TABLE `marine-cycle-484213-b4.dianplus.core_dianplus_inventory`
(
  proc_date TIMESTAMP,
  updated_at DATE,
  brandId INT64,
  warehouse_name STRING,
  spuId INT64,
  spuCode STRING,
  skuId INT64,
  product_code STRING,
  product_launch_date DATE,
  skuCode STRING,
  realNum INT64,
  lockNum INT64,
  canUseNum INT64,
  frozenNum INT64,
  transitNum INT64,
  defectNum INT64
)
PARTITION BY updated_at
CLUSTER BY proc_date, skuId, skuCode;
