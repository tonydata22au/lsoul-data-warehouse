CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_sale_online_vn_v2`(
  i_number_year_back INT64 -- number of years back from current year
  , i_type  INT64 --0: Base order by datetime
)
AS 
(
--SALE ONLINE
-- SELECT *,EXCEPT(variation_code,product_code,product_name,product_launch_date, variation_attributes,retail_price,warehouse_id,warehouse_name)FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_vn_v2`(0,0) ORDER BY 1 DESC
-- SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_vn_v2`(0,1) ORDER BY 1 DESC
-- SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_sale_online_vn_v2`(0,3) ORDER BY 1 DESC
WITH stage AS (
  SELECT
      order_date,
      o.order_id,
      CASE WHEN o.order_id IN (SELECT CAST(order_id AS STRING) FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` where is_duplicate = 0) and status_name = 'delivered' THEN 'part-returned' ELSE status_name END AS status_name,

      'Sale Online' AS level_1,
      'VN Online' AS level_2,
      order_sources_name AS level_3,
      CAST(customer_id AS STRING) AS customer_id,
      CASE 
        WHEN tags LIKE '%Facebook%'   THEN 'Facebook'
        WHEN tags LIKE '%Instagram%'  THEN 'Instagram'
        WHEN tags LIKE '%Tiktok%'     THEN 'Tiktok'
        WHEN tags LIKE '%Website%' OR  tags LIKE '%Google%' THEN 'Online Ads'
        WHEN tags LIKE '%Shopee%'     THEN 'Shopee'
        WHEN tags LIKE '%XIAO%'       THEN 'Xiaohongshu'
       ELSE order_sources_name
      END AS customer_from_ads_source,

      --PRODUCT
      oi.product_id,
      p.product_code,
      oi.product_name,
      v.variation_display_id AS variation_code,
      v.variation_attributes,
      p.product_launch_date,
      oi.retail_price,
      CASE WHEN LEFT(variation_display_id,2) IN ('TG','HT','HN','HH','TD') THEN 1 ELSE 0 END AS to_remove_sku,
      CASE WHEN TRIM(UPPER(p.product_tags)) LIKE '%SYS_01_SALE_END%' THEN 1 ELSE 0 END is_sale_end,

      --WAREHOUSE
      oi.warehouse_id,
      oi.warehouse_name,

      --SALE
      customer_currency,
      CASE 
        WHEN customer_currency = 'USD' THEN 260 
        WHEN customer_currency = 'MYR' THEN 65 
        WHEN customer_currency = 'PHP' THEN 4
        WHEN customer_currency = 'SGD' THEN 202.66
        ELSE 1 END * oi.sales_revenue AS sales_revenue,
      CASE 
        WHEN customer_currency = 'USD' THEN 260 
        WHEN customer_currency = 'MYR' THEN 65 
        WHEN customer_currency = 'PHP' THEN 4
        WHEN customer_currency = 'SGD' THEN 202.66
        ELSE 1 END * item_total_discount AS discount,
      CASE 
        WHEN customer_currency = 'USD' THEN 260 
        WHEN customer_currency = 'MYR' THEN 65 
        WHEN customer_currency = 'PHP' THEN 4
        WHEN customer_currency = 'SGD' THEN 202.66
        ELSE 1 END * advanced_platform_fee_marketplace_voucher AS ecom_voucher,
      CASE 
        WHEN customer_currency = 'USD' THEN 260 
        WHEN customer_currency = 'MYR' THEN 65 
        WHEN customer_currency = 'PHP' THEN 4
        WHEN customer_currency = 'SGD' THEN 202.66
        ELSE 1 END * total_discount AS total_discount,
      CASE WHEN LEFT(variation_display_id,2) NOT IN ('TG','HT','HN','HH','TD') THEN oi.cart_quantity ELSE 0 END AS item_qty,

       --ORDER DETAILS
      CASE WHEN o.order_id IN (SELECT CAST(order_id AS STRING) FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` where is_duplicate = 0) THEN 1 ELSE 0 END is_returned_order,
      is_exchange_order,
      exchange_value,
      -- assigning_seller_name,creator_name

      CASE
            WHEN oi.cart_quantity <= 0 THEN 1
            WHEN o.total_price <= 0 THEN 1
            WHEN status_name  IN ('canceled','returned','packing') THEN 1
            --WHEN LEFT(variation_display_id,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN 1
            ELSE 0
      END to_remove_record

    FROM `marine-cycle-484213-b4.core_pancake.core_order_item` AS oi
    JOIN `marine-cycle-484213-b4.core_pancake.core_order` AS o ON oi.order_id = o.order_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_id = p.raw_product_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.variation_id = v.variation_id
    WHERE 1=1
      AND o.order_id NOT IN (SELECT CAST(order_id AS STRING) FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` WHERE is_duplicate = 1)
      AND (
          assigning_seller_name IN ('OANHONLINE','TLINHONLINE','TAIONLINE', 'TRAM XLD', 'Bao Tran XLD') 
          OR creator_name IN ('QUINT','OANHONLINE','TLINHONLINE','TAIONLINE', 'TRAM XLD', 'Bao Tran XLD'))
      AND (o.order_sources_name IN ('Website', 'Facebook', 'Webcake', 'Instagram', 'Zalo') OR o.warehouse_name = 'Kho Online')
)
,core AS (
  SELECT
  * EXCEPT (total_discount,is_returned_order,item_qty,sales_revenue,discount)
  ,CASE WHEN to_remove_record = 0 THEN item_qty ELSE 0 END AS item_qty
  ,CASE WHEN to_remove_record = 0 THEN sales_revenue ELSE 0 END AS sales_revenue
  ,CASE WHEN to_remove_record = 0 THEN discount ELSE 0 END AS discount
  ,CASE WHEN is_returned_order = 1 THEN 0 ELSE total_discount END AS order_total_discount
  ,CASE 
          WHEN to_remove_record = 0
          THEN SAFE_DIVIDE(
                      (ecom_voucher - total_discount)
                      ,SUM(CASE WHEN to_remove_sku = 0 THEN 1 ELSE 0 END) OVER (PARTITION BY order_id ORDER BY order_id)
                      )
          ELSE 0 END
    AS extra_sale_revenue
  FROM stage
)   
   --When i_type = 0, the data is grouped by order_date, and the grain is at level 3.
  SELECT --*
  * EXCEPT (product_id,product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue,discount,ecom_voucher,order_total_discount,item_qty, extra_sale_revenue,is_exchange_order,exchange_value,to_remove_record),
  '' AS variation_code,
  '' product_code, '' product_name, CAST(NULL AS DATE) product_launch_date, ''  variation_attributes, null retail_price,''  warehouse_id,'' warehouse_name,
  SUM(item_qty) AS total_units_sold,
  SUM(sales_revenue) AS sales_revenue,
  ROUND(SUM(extra_sale_revenue),0) AS extra_sale_revenue,
  SUM(discount) AS discount,
  ROUND(SUM(sales_revenue - discount + extra_sale_revenue),0) AS revenue

  FROM core
  WHERE 1=1
      AND i_type = 0
      AND to_remove_record = 0
      AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
      --AND DATE_TRUNC(order_date, YEAR) >='2026-01-01' 
      --AND DATE_TRUNC(order_date, day) between '2025-11-01' and '2025-11-30'
      --AND DATE(order_date) = '2026-07-11'
      --AND order_id = '43593'
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8,9

  UNION ALL

  --When i_type = 1, the data is grouped by level_3, and the grain is at variation_code.
  SELECT --*
  * EXCEPT (product_id,product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue,discount,ecom_voucher,order_total_discount,item_qty, extra_sale_revenue,is_exchange_order,exchange_value,to_remove_record),
  variation_code,
  '' product_code, '' product_name, CAST(NULL AS DATE) product_launch_date, ''  variation_attributes, null retail_price,''  warehouse_id,'' warehouse_name,
  SUM(item_qty) AS total_units_sold,
  SUM(sales_revenue) AS sales_revenue,
  ROUND(SUM(extra_sale_revenue),0) AS extra_sale_revenue,
  SUM(discount) AS discount,
  ROUND(SUM(sales_revenue - discount + extra_sale_revenue),0) AS revenue

  FROM core
  WHERE 1=1
      AND i_type = 1
      AND to_remove_record = 0
      AND to_remove_sku = 0
      AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
      --AND DATE_TRUNC(order_date, YEAR) >='2026-01-01' 
      --AND DATE_TRUNC(order_date, day) between '2025-11-01' and '2025-11-30'
      --AND DATE(order_date) = '2026-07-11'
      --AND order_id = '43593'
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8,9,10

  UNION ALL

  --When i_type = 3, the data is grouped by variation_code, and the grain is at warehouse_id.
  SELECT --*
  * EXCEPT (product_id,product_code,product_name,product_launch_date, variation_code, variation_attributes,retail_price,to_remove_sku,is_sale_end,warehouse_id,warehouse_name,sales_revenue,discount,ecom_voucher,order_total_discount,item_qty, extra_sale_revenue,is_exchange_order,exchange_value,to_remove_record),
  variation_code,
  product_code,product_name,product_launch_date, variation_attributes,retail_price,warehouse_id,warehouse_name,
  SUM(item_qty) AS total_units_sold,
  SUM(sales_revenue) AS sales_revenue,
  ROUND(SUM(extra_sale_revenue),0) AS extra_sale_revenue,
  SUM(discount) AS discount,
  ROUND(SUM(sales_revenue - discount + extra_sale_revenue),0) AS revenue

  FROM core
  WHERE 1=1
      AND i_type = 3
      AND to_remove_record = 0
      AND to_remove_sku = 0
      AND DATE_TRUNC(order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
      --AND DATE_TRUNC(order_date, YEAR) >='2026-01-01' 
      --AND DATE_TRUNC(order_date, day) between '2025-11-01' and '2025-11-30'
      --AND DATE(order_date) = '2026-07-11'
      --AND order_id = '43593'
  GROUP BY 1, 2, 3, 4, 5, 6, 7,8,9,10,11,12,13,14,15,16,17

  ORDER BY 1 DESC, 2 
)
    
   