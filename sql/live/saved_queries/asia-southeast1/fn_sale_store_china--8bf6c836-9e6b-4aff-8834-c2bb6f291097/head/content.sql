CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(
  i_number_year_back INT64 -- number of years back from current year
  ,i_type  INT64 --0: Base order by datetime
)
AS 
(
/********
--SALE STORE CHINA

SELECT * * EXCEPT(variation_code,product_code,product_name,product_launch_date, variation_attributes,retail_price,warehouse_id,warehouse_name) FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(0,0) ORDER BY 1 DESC
SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(0,1) ORDER BY 1 DESC
SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(0,3) ORDER BY revenue_vn ASC
****/

WITH dim_product AS (
  -- ONE row per product_code. This is the entire fix.
  SELECT
     product_code
    ,ANY_VALUE(product_name)        AS product_name
    ,ANY_VALUE(product_launch_date) AS product_launch_date
    ,MAX(CASE WHEN TRIM(UPPER(product_tags)) LIKE '%SYS_01_SALE_END%' THEN 1 ELSE 0 END) AS is_sale_end
  FROM `marine-cycle-484213-b4.core_pancake.core_product`
  GROUP BY product_code
)
,stage AS (
SELECT
      o.inserted_at AS order_date,
      o.orderId AS order_id, 
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
      END AS status_name,
      -- CASE o.orderType
      --     WHEN 1  THEN 'Normal'
      --     WHEN 2  THEN 'Out of Stock Pre-order'
      --     WHEN 3  THEN 'In Stock'
      --     WHEN 4  THEN 'Mall Pre-sale'
      --     WHEN 5  THEN 'Product Pre-sale'
      --     WHEN 6  THEN 'Other types'
      --     WHEN 7  THEN 'All types'
      --     WHEN 8  THEN 'Service order type'
      --     WHEN 9  THEN 'Shipped order type'
      --     WHEN 99 THEN 'Unknown'
      --     ELSE 'Unknown'
      -- END AS orderType_desc,
      -- o.order_source_id 
      'Store' AS level_1,
      'TQ Offline Store' AS level_2,
      'Store TXmall' AS level_3,
      CAST(vipMobilePhone AS STRING) AS customer_id,

      --PRODUCT
      p.product_code,
      IFNULL(p.product_name,oi.skuName) AS product_name,
      oi.skuCode AS variation_code,
      v.variation_attributes,
      p.product_launch_date,
      oi.suggestPrice AS retail_price,
      CASE WHEN LEFT(IFNULL(variation_display_id,oi.skuCode),2) IN ('TG','HT','HN','HH','TD') THEN 1 ELSE 0 END AS to_remove_sku,
      IFNULL(is_sale_end,0) AS is_sale_end,
      --serviceGuides_staffName,

      --WAREHOUSE
      '76be7836-6dc5-4b1c-9e48-b18e43127453' AS warehouse_id, --warehouse_id cua Kho Trung Quốc (Back-up)
      'Kho Trung Quốc (Back-up)' AS warehouse_name,

      --SALE
      oi.sumSuggestPrice AS sales_revenue_cn_gmv,
      oi.sumSalePrice  AS revenue_cn_gmv,
      IFNULL(returnMoney,0)  AS refund,
      CASE 
          WHEN oi.sumSuggestPrice - oi.sumSalePrice - IFNULL(returnMoney,0)  < 0 THEN 0 
          ELSE oi.sumSuggestPrice - oi.sumSalePrice - IFNULL(returnMoney,0) END 
      AS discount,
      CASE WHEN LEFT(IFNULL(variation_display_id,oi.skuCode),2) NOT IN ('TG','HT','HN','HH','TD') THEN oi.amount ELSE 0  END AS item_qty,
      IFNULL(returnAmount,0) AS item_return_qty,
      
      CASE
          WHEN oi.amount <= 0 THEN 1
          ELSE 0
      END to_remove_record

    FROM `marine-cycle-484213-b4.dianplus.core_dianplus_order` AS o
    JOIN `marine-cycle-484213-b4.dianplus.core_dianplus_order_item` AS oi ON oi.orderID = o.orderId 
    LEFT JOIN `marine-cycle-484213-b4.dianplus.core_dianplus_order_item_refund`AS ri ON o.orderId = ri.porderId AND oi.skuDjId = ri.skuDjId
    LEFT JOIN dim_product AS p ON oi.product_code = p.product_code
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.skuCode = v.variation_display_id
    WHERE 1=1    
)
,core AS (
    SELECT
    * EXCEPT (item_qty,discount)
    ,CASE WHEN to_remove_record = 0 THEN IF(item_qty = 0,item_return_qty,item_qty) - item_return_qty ELSE 0 END AS item_qty
    ,CASE WHEN to_remove_record = 0 THEN sales_revenue_cn_gmv ELSE 0 END AS sales_revenue_cn --nmv
    ,CASE WHEN to_remove_record = 0 THEN revenue_cn_gmv - refund ELSE 0 END AS revenue_cn --nmv
    ,CASE WHEN to_remove_record = 0 THEN discount ELSE 0 END AS discount
    FROM stage
)
  --When i_type = 0, the data is grouped by order_date, and the grain is at level 3.
  SELECT 
   * EXCEPT (product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue_cn_gmv,revenue_cn_gmv,refund,discount,item_qty,item_return_qty,to_remove_record,sales_revenue_cn,revenue_cn),
  '' AS variation_code,
  '' product_code, '' product_name, CAST(NULL AS DATE) product_launch_date, ''  variation_attributes, null retail_price, ''  warehouse_id, '' warehouse_name,
  SUM(item_qty) AS total_units_sold,
  ROUND(SUM(sales_revenue_cn_gmv),2) AS sales_revenue_cn_gmv,
  ROUND(SUM(revenue_cn_gmv),2) AS revenue_cn_gmv,
  SUM(discount) AS discount,
  SUM(refund) AS refund,
  ROUND(SUM(sales_revenue_cn),2) AS sales_revenue_cn, --nmv
  ROUND(SUM(revenue_cn),2) AS revenue_cn, --nmv
  ROUND(SUM(sales_revenue_cn * 3800),0) AS sales_revenue_vn, --nmv
  ROUND(SUM(revenue_cn * 3800),0) AS revenue_vn --nmv
  FROM core   
  WHERE 1=1
  AND i_type = 0
  AND to_remove_record = 0
  AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8

  UNION ALL
  
  --When i_type = 1, the data is grouped by level_3, and the grain is at variation_code.
  SELECT 
   * EXCEPT (product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue_cn_gmv,revenue_cn_gmv,refund,discount,item_qty,item_return_qty,to_remove_record,sales_revenue_cn,revenue_cn),
  variation_code,
  '' product_code, '' product_name, CAST(NULL AS DATE) product_launch_date, ''  variation_attributes, null retail_price, ''  warehouse_id, '' warehouse_name,
  SUM(item_qty) AS total_units_sold,
  ROUND(SUM(sales_revenue_cn_gmv),2) AS sales_revenue_cn_gmv,
  ROUND(SUM(revenue_cn_gmv),2) AS revenue_cn_gmv,
  SUM(discount) AS discount,
  SUM(refund) AS refund,
  ROUND(SUM(sales_revenue_cn),2) AS sales_revenue_cn, --nmv
  ROUND(SUM(revenue_cn),2) AS revenue_cn, --nmv
  ROUND(SUM(sales_revenue_cn * 3800),0) AS sales_revenue_vn, --nmv
  ROUND(SUM(revenue_cn * 3800),0) AS revenue_vn --nmv
  FROM core   
  WHERE 1=1
  AND i_type = 1
  AND to_remove_record = 0
  AND to_remove_sku = 0
  AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8

  UNION ALL
  
  --When i_type = 3, the data is grouped by variation_code, and the grain is at warehouse_id.
  SELECT 
   * EXCEPT (product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue_cn_gmv,revenue_cn_gmv,refund,discount,item_qty,item_return_qty,to_remove_record,sales_revenue_cn,revenue_cn),
  variation_code,
  product_code,product_name,product_launch_date, variation_attributes,retail_price,warehouse_id,warehouse_name,
  SUM(item_qty) AS total_units_sold,
  ROUND(SUM(sales_revenue_cn_gmv),2) AS sales_revenue_cn_gmv,
  ROUND(SUM(revenue_cn_gmv),2) AS revenue_cn_gmv,
  SUM(discount) AS discount,
  SUM(refund) AS refund,
  ROUND(SUM(sales_revenue_cn),2) AS sales_revenue_cn, --nmv
  ROUND(SUM(revenue_cn),2) AS revenue_cn, --nmv
  ROUND(SUM(sales_revenue_cn * 3800),0) AS sales_revenue_vn, --nmv
  ROUND(SUM(revenue_cn * 3800),0) AS revenue_vn --nmv
  FROM core   
  WHERE 1=1
  AND i_type = 3
  AND to_remove_record = 0
  AND to_remove_sku = 0
  AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8,9,10,11,12,13,14,15

)