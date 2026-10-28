CREATE TABLE `marine-cycle-484213-b4.dianplus.raw_dianplus_inventory`
(
  inserted_at STRING,
  brandId STRING,
  storageId STRING,
  spuId STRING,
  spuCode STRING,
  skuId STRING,
  skuCode STRING,
  realNum STRING,
  lockNum STRING,
  canUseNum STRING,
  frozenNum STRING,
  transitNum STRING,
  defectNum STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
