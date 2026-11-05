--truncate table `marine-cycle-484213-b4.dianplus.core_dianplus_order_refund`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.dianplus.core_dianplus_order_refund`
PARTITION BY DATE(inserted_at)
CLUSTER BY  porderId,applyTime, rorderId
OPTIONS (
  require_partition_filter=false
) AS
SELECT DISTINCT
inserted_at,
brandId,
porderId,
orderId,
rorderId,
applyTime,
returnTime,
lastModifyTime,
refundStatus,
orderType,
returnSource,
srcSystem,
returnType,
saleChannelId,
saleChannelDjId,
saleChannelCode,
saleShopDjId,
saleShopCode,
saleStaffDjId,
saleStaffCode,
deliverShopDjId,
deliverShopCode,
deliverChannelCode,
deliverStaffDjId,
deliverStaffCode,
returnShopDjId,
returnShopCode,
returnChannelCode,
returnStaffDjId,
returnStaffCode,
returnNum,
sumSuggestPrice,
returnMoney,
remark,
serviceGuides_staffDjId,
serviceGuides_staffCode,
payInfos_payType,
payInfos_payCode,
payInfos_outPayChannelDesc,
payInfos_amount,
payInfos_otherAmount,
payInfos_cashVoucherDtos,
origOrder_orderId,
origOrder_sumAmount,
origOrder_sumSuggestPrice,
origOrder_sumSalePrice,
origOrder_sumDealPrice
FROM `marine-cycle-484213-b4.dianplus.stg_dianplus_order_refund`
WHERE DATE(proc_date) >= "2026-04-25"