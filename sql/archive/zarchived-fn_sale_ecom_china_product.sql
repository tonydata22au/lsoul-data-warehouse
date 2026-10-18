CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_sale_ecom_china_product`(
  number_year_back INT64 -- number of years back from current year
)
AS 
--Sale Ecommerce China
WITH dim_product AS (
  -- ONE row per product_code. This is the entire fix.
  SELECT
     product_code
    ,ANY_VALUE(product_name)        AS product_name
    ,ANY_VALUE(product_launch_date) AS product_launch_date
    ,MAX(CASE WHEN TRIM(UPPER(product_tags)) LIKE '%SYS_01_SALE_END%'  THEN 1 ELSE 0 END) AS is_sale_end
  FROM `marine-cycle-484213-b4.core_pancake.core_product`
  GROUP BY product_code
)
,base_order_daily AS (
  SELECT DISTINCT
      o.o_id AS order_id
      ,o.so_id
      ,o.vn_order_date AS order_date
      ,oi.product_code
      ,IFNULL(product_name, oi.items_name) AS product_name
      ,oi.items_sku_id AS variation_code
      ,v.variation_attributes
      ,oi.product_launch_date
      ,items_base_price * 3800 AS retail_price
      ,IFNULL(p.is_sale_end, 0) AS is_sale_end
      ,o.status
      ,'Sale Ecommerce' AS order_sources_name
      ,CASE 
        WHEN shop_name LIKE '%Douyin%' or LEFT(UPPER(o.raw_so_id),1) = '6' THEN 'Douyin'
        ELSE shop_name
        END AS channel
      ,'TQ Ecommerce' AS sale_channel
      ,'Douyin' AS sale_channel_details
      ,buyer_id
      ,o.order_from
      ,'76be7836-6dc5-4b1c-9e48-b18e43127453' AS warehouse_id --warehouse_id cua Kho Trung Quốc (Back-up)
      ,'Kho Trung Quốc (Back-up)' AS warehouse_name
      ,CASE
            WHEN UPPER(oi.items_status) LIKE '%CANCELLED%' THEN 1
            WHEN LEFT(oi.items_sku_id,2) IN ('TG','HT','HN','HH','TD','TU') THEN 1
            ELSE 0
          END to_remove_record
      ,oi.items_qty                                                             AS units_sold
      ,IF(IS_NAN(items_base_price), 0, items_base_price)                        AS sale_revenue_cn
      ,IF(IS_NAN(items_buyer_paid_amount), 0, items_buyer_paid_amount)          AS revenue_cn
      ,IF(IS_NAN(items_buyer_paid_amount), 0, items_buyer_paid_amount) * 3800   AS revenue_vn
    FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_order` AS o
    JOIN `marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item` AS oi ON o.o_id = oi.o_id
    LEFT JOIN dim_product p ON oi.product_code = p.product_code
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.items_sku_id = v.variation_display_id
    WHERE 1=1
      AND DATE_TRUNC(o.vn_order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.order_date, day) between '2026-02-01' and '2026-02-28'
      --AND raw_so_id = '6924076713027337292'
      AND (shop_name LIKE '%Douyin%' or LEFT(UPPER(o.raw_so_id),1) = '6')

  UNION ALL

  SELECT DISTINCT
      o.o_id AS order_id
      ,o.so_id
      ,o.vn_order_date AS order_date
      ,oi.product_code
      ,IFNULL(product_name, oi.items_name) AS product_name
      ,oi.items_sku_id AS variation_code
      ,v.variation_attributes
      ,oi.product_launch_date
      ,items_price * 3800 AS retail_price
      ,CASE WHEN TRIM(UPPER(p.product_tags)) = 'SYS_01_SALE_END' THEN 1 ELSE 0 END is_sale_end
      ,o.status
      ,'Sale Ecommerce' AS order_sources_name
      ,CASE 
        WHEN shop_name LIKE '%Xiaohongshu%' or LEFT(UPPER(o.raw_so_id),1) = 'P' Then 'Xiaohongshu'
        ELSE shop_name
        END AS channel
      ,'TQ Ecommerce' AS sale_channel
      ,'Xiaohongshu' AS sale_channel_details
      ,buyer_id
      ,o.order_from
      ,'76be7836-6dc5-4b1c-9e48-b18e43127453' AS warehouse_id --warehouse_id cua Kho Trung Quốc (Back-up)
      ,'Kho Trung Quốc (Back-up)' AS warehouse_name
      ,CASE
        WHEN oi.items_refund_status LIKE 'success' AND status LIKE 'Cancelled' THEN 1
        WHEN IFNULL(SAFE_CAST(oi.items_seller_income_amount AS NUMERIC),0) <= 0 THEN 1
        WHEN LEFT(oi.items_sku_id,2) IN ('TG','HT','HN','HH','TD','TU') THEN 1
        ELSE 0
      END to_remove_record
      ,oi.items_qty                       AS units_sold
      ,IF(IS_NAN(items_base_price), 0, items_base_price)                        AS sale_revenue_cn
      ,IF(IS_NAN(items_buyer_paid_amount), 0, items_buyer_paid_amount)          AS revenue_cn
      ,IF(IS_NAN(items_buyer_paid_amount), 0, items_buyer_paid_amount) * 3800   AS revenue_vn
    FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_order` AS o
    JOIN `marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item` AS oi ON o.so_id = oi.so_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_code = p.product_code
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.items_sku_id = v.variation_display_id
    WHERE 1=1
      AND DATE_TRUNC(o.vn_order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.order_date, day) between '2026-02-01' and '2026-02-28'
      --AND o.raw_so_id = 'P786067418108099451'
      AND (shop_name LIKE '%Xiaohongshu%' or LEFT(UPPER(o.raw_so_id),1) = 'P')
      AND NOT (status = 'Merged' AND o.so_id IN (SELECT so_id FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_order` WHERE is_merge = 1))
)
SELECT
* EXCEPT (to_remove_record)
FROM base_order_daily
WHERE 1=1
  AND to_remove_record = 0
    ORDER BY channel,order_date

