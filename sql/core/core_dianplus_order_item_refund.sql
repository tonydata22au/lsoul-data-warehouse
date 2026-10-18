--drop table `marine-cycle-484213-b4.dianplus.core_dianplus_order_item_refund`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.dianplus.core_dianplus_order_item_refund`
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
returnOrderItems_rorderItemId AS rorderItemId,
returnOrderItems_spuDjId AS spuDjId,
returnOrderItems_spuCode AS spuCode,
returnOrderItems_skuDjId AS skuDjId,
REGEXP_EXTRACT(returnOrderItems_skuCode, r'^([^-]+)') AS product_code,
   DATE(
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(returnOrderItems_skuCode, r'\d{6}'), 1, 2) AS INT64) + 2000,
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(returnOrderItems_skuCode, r'\d{6}'), 3, 2) AS INT64),
    01
    ) product_launch_date,
returnOrderItems_skuCode AS skuCode,
returnOrderItems_colorCode AS colorCode,
returnOrderItems_colorName AS colorName,
returnOrderItems_sizeCode AS sizeCode,
returnOrderItems_sizeName AS sizeName,
returnOrderItems_returnAmount AS returnAmount,
returnOrderItems_suggestPrice AS suggestPrice,
returnOrderItems_salePrice AS salePrice,
returnOrderItems_dealPrice AS dealPrice,
returnOrderItems_sumSuggestPrice AS sumSuggestPrice,
returnOrderItems_sumSalePrice AS sumSalePrice,
returnOrderItems_returnMoney AS returnMoney,
returnOrderItems_returnStaffId AS returnStaffId,
returnOrderItems_returnStaffDjId AS returnStaffDjId,
returnOrderItems_returnStaffCode AS returnStaffCode,
returnOrderItems_cashDtos AS cashDtos,
returnOrderItems_uniqueCodes AS uniqueCodes,
returnOrderItems_itemPayInfos_payMethodCode AS payMethodCode,
returnOrderItems_itemPayInfos_payMethodDesc AS payMethodDesc,
returnOrderItems_itemPayInfos_custPayMethodCode AS custPayMethodCode,
returnOrderItems_itemPayInfos_custPayMethodName AS custPayMethodName,
returnOrderItems_itemPayInfos_amt AS amt,
returnOrderItems_itemPayInfos_totalAmt AS totalAmt
FROM `marine-cycle-484213-b4.dianplus.stg_dianplus_order_refund`
WHERE DATE(proc_date) = "2026-04-25"