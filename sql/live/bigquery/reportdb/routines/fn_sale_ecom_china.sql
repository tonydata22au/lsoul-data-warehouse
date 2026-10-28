CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_ecom_china(number_year_back INT64)
AS
WITH CTE AS (
  SELECT 
      o.o_id AS order_id
      ,o.so_id
      ,o.vn_order_date AS order_date
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
        --WHEN LEFT(oi.items_sku_id,2) IN ('TG','HT','HN','HH','TD','TU') THEN 1
        ELSE 0
      END to_remove_record
      ,items_sku_id
      ,product_code
      ,items_qty
      ,IF(IS_NAN(items_base_price), 0, items_base_price) AS items_base_price
      ,IF(IS_NAN(items_buyer_paid_amount), 0, items_buyer_paid_amount) AS items_buyer_paid_amount
    FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_order` AS o
    JOIN `marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item` AS oi
      ON o.o_id = oi.o_id
    WHERE 1=1
      AND DATE_TRUNC(o.vn_order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.order_date, day) between '2026-02-01' and '2026-02-28'
      --AND raw_so_id = '6924076713027337292'
      AND (shop_name LIKE '%Douyin%' or LEFT(UPPER(o.raw_so_id),1) = '6')

  UNION ALL

  SELECT
      o.o_id AS order_id
      ,o.so_id
      ,o.vn_order_date AS order_date
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
        --WHEN LEFT(oi.items_sku_id,2) IN ('TG','HT','HN','HH','TD','TU') THEN 1
        ELSE 0
      END to_remove_record
      -- ,CASE WHEN TRIM(oi.items_refund_status) LIKE 'success' AND TRIM(status) LIKE 'Cancelled' THEN 0
      --       WHEN IFNULL(SAFE_CAST(oi.items_seller_income_amount AS NUMERIC),0) > 0 THEN 1
      --       ELSE 1 
      --       END AS is_order_confirmed
      ,items_sku_id
      ,product_code
      ,items_qty
      ,IF(IS_NAN(items_base_price), 0, items_base_price) AS items_base_price
      ,IF(IS_NAN(items_buyer_paid_amount), 0, items_buyer_paid_amount) AS items_buyer_paid_amount
    FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_order` AS o
    JOIN `marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item` AS oi
      ON o.so_id = oi.so_id
    WHERE 1=1
      AND DATE_TRUNC(o.vn_order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.order_date, day) between '2026-02-01' and '2026-02-28'
      --AND o.raw_so_id = 'P786067418108099451'
      AND (shop_name LIKE '%Xiaohongshu%' or LEFT(UPPER(o.raw_so_id),1) = 'P')
      AND NOT (status = 'Merged' AND o.so_id IN (SELECT so_id FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_order` WHERE is_merge = 1))
)

SELECT
*  EXCEPT (items_sku_id,product_code,items_qty,items_buyer_paid_amount,items_base_price,to_remove_record)
,COUNT(DISTINCT CASE WHEN to_remove_record = 0 THEN order_id END) AS total_orders
,COUNT(DISTINCT CASE WHEN LEFT(items_sku_id,2) NOT IN ('TG','HT','HN','HH','TD','TU') AND to_remove_record = 0 THEN product_code END) AS total_products
,SUM(CASE WHEN LEFT(items_sku_id,2) NOT IN ('TG','HT','HN','HH','TD','TU') AND to_remove_record = 0 THEN items_qty ELSE 0 END) AS total_units_sold
  ,SUM(items_base_price) AS sale_revenue_cn_gmv
  ,SUM(items_buyer_paid_amount)  AS revenue_cn_gmv
  ,SUM(CASE WHEN to_remove_record = 0 THEN items_base_price ELSE 0 END) sale_revenue_cn --nmv
  ,SUM(CASE WHEN to_remove_record = 0 THEN items_buyer_paid_amount ELSE 0 END) revenue_cn --nmv
  ,SUM(CASE WHEN to_remove_record = 0 THEN items_base_price * 3800 ELSE 0 END) sale_revenue_vn --nmv
  ,SUM(CASE WHEN to_remove_record = 0 THEN items_buyer_paid_amount * 3800 ELSE 0 END) revenue_vn --nmv
FROM CTE
GROUP BY 1, 2, 3,4,5, 6,7,8,9,10,11,12
ORDER BY 1 DESC, 2;
