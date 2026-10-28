CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_store_china(number_year_back INT64)
AS
WITH ORDER_REFUND AS (
  SELECT
  porderId,
  SUM(returnNum) AS units_refrund,
  SUM(returnMoney) AS amount_refund
  FROM `marine-cycle-484213-b4.dianplus.core_dianplus_order_refund`
  GROUP BY porderId
)

SELECT
      o.orderId, 
      o.inserted_at AS order_date,
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
      COUNT(distinct o.orderId) AS total_orders,
      COUNT(DISTINCT CASE WHEN LEFT(oi.skuCode,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.product_code END) AS total_products,
      SUM( CASE WHEN LEFT(oi.skuCode,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.amount ELSE 0 END) -  IFNULL(units_refrund,0)  AS total_units_sold,
      IFNULL(units_refrund,0)  AS total_units_refrund,
      SUM(oi.sumSalePrice) - IFNULL(amount_refund,0)   AS revenue_cn,
      ROUND((SUM(oi.sumSalePrice) - IFNULL(amount_refund,0)) * 3800,0) AS revenue_vn,
      SUM(oi.sumSuggestPrice) AS sales_revenue_cn,
      SUM(oi.sumSuggestPrice *3800) AS sales_revenue_vn,
      IFNULL(amount_refund,0)  AS total_amount_refund,

      CASE WHEN SUM(oi.sumSuggestPrice) - SUM(oi.sumSalePrice) - IFNULL(amount_refund,0)  < 0 THEN 0 ELSE SUM(oi.sumSuggestPrice) - SUM(oi.sumSalePrice) - IFNULL(SUM(amount_refund),0) END AS discount_amount
    FROM `marine-cycle-484213-b4.dianplus.core_dianplus_order` AS o
    LEFT JOIN `marine-cycle-484213-b4.dianplus.core_dianplus_order_item` AS oi ON oi.orderID = o.orderId AND oi.amount > 0
    LEFT JOIN ORDER_REFUND AS r ON o.orderId = r.porderId
    WHERE 1=1    
      --AND o.orderId = '1217154050832211969'
      --AND DATE_TRUNC(o.inserted_at, day) between '2026-02-01' and '2026-02-28'
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
    GROUP BY 1, 2, 3, 4, 5,9,10, units_refrund, amount_refund
    ORDER BY 2,1, 4;
