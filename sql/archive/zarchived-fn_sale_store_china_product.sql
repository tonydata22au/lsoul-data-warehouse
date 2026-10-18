CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_sale_store_china_product`(
  number_year_back INT64 -- number of years back from current year
)
AS 
(
/********
SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_product`(1)
****/
--SALE STORE CHINA
SELECT DISTINCT
      o.orderId AS order_id,
      o.inserted_at AS order_date,
      oi.product_code,
      IFNULL(p.product_name,oi.skuName) AS product_name,
      oi.skuCode AS variation_code,
      v.variation_attributes,
      oi.product_launch_date,
      oi.suggestPrice AS retail_price,
      CASE WHEN TRIM(UPPER(p.product_tags)) = 'SYS_01_SALE_END' THEN 1 ELSE 0 END is_sale_end, 
      oi.skuDjId,
      CASE o.orderType
          WHEN 1  THEN 'Normal'
          WHEN 2  THEN 'Out of Stock Pre-order'
          WHEN 3  THEN 'In Stock'
          WHEN 4  THEN 'Mall Pre-sale'
          WHEN 5  THEN 'Product Pre-sale'
          WHEN 6  THEN 'Other types'
          WHEN 7  THEN 'All types'
          WHEN 8  THEN 'Service order type'
          WHEN 9  THEN 'Shipped order type'
          WHEN 99 THEN 'Unknown'
          ELSE 'Unknown'
      END AS orderType_desc, 
      CASE o.orderStatus
          WHEN 1  THEN 'Pending shipment'
          WHEN 2  THEN 'Pending receipt'
          WHEN 3  THEN 'Completed'
          WHEN 4  THEN 'Pending pickup'
          WHEN 5  THEN 'Picked up'
          WHEN 6  THEN 'Pending payment'
          WHEN 7  THEN 'Full payment received'
          WHEN 8  THEN 'Closed'
          WHEN 9  THEN 'All'
          WHEN 10 THEN 'Pending claim'
          WHEN 11 THEN 'Partial shipment'
          WHEN 12 THEN 'Partial payment received'
          WHEN 18 THEN 'Cancelled'
          WHEN 19 THEN 'Locked'
          WHEN 99 THEN 'Unknown'
          ELSE 'Unknown'
      END AS orderStatus_desc,
      o.order_source_id,
      'TQ Offline Store' AS sale_channel,
      '76be7836-6dc5-4b1c-9e48-b18e43127453' AS warehouse_id, --warehouse_id cua Kho Trung Quốc (Back-up)
      'Kho Trung Quốc (Back-up)' AS warehouse_name,
      serviceGuides_staffName,
      vipMobilePhone,
      oi.amount - IFNULL(returnAmount,0)  AS units_sold,
      oi.sumSalePrice - IFNULL(returnMoney,0) AS revenue_cn,
      ROUND((oi.sumSalePrice - IFNULL(returnMoney,0))*3800,0) AS revenue_vn,
      oi.sumSuggestPrice AS sales_revenue_cn,
      oi.sumSuggestPrice *3800 AS sales_revenue_vn,
      IFNULL(returnMoney,0)  AS total_amount_refund,
      CASE 
          WHEN oi.sumSuggestPrice - oi.sumSalePrice - IFNULL(returnMoney,0)  < 0 
          THEN 0 
          ELSE oi.sumSuggestPrice - oi.sumSalePrice - IFNULL(returnMoney,0) 
      END AS discount_amount
      
    FROM `marine-cycle-484213-b4.dianplus.core_dianplus_order` AS o
    JOIN `marine-cycle-484213-b4.dianplus.core_dianplus_order_item` AS oi ON oi.orderID = o.orderId 
    LEFT JOIN `marine-cycle-484213-b4.dianplus.core_dianplus_order_item_refund`AS ri ON o.orderId = ri.porderId AND oi.skuDjId = ri.skuDjId
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_code = p.product_code
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.skuCode = v.variation_display_id
    WHERE 1=1    
      --AND o.orderId = '1217154050832211969'
      --AND DATE_TRUNC(o.inserted_at, day) between '2026-02-01' and '2026-02-28'
    AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
    AND LEFT(oi.skuCode,2) NOT IN ('TG','HT','HN','HH','TD')
    AND oi.amount > 0
    ORDER BY 1,3
)
    
   