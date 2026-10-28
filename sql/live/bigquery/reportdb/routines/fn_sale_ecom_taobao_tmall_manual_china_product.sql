CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_ecom_taobao_tmall_manual_china_product(number_year_back INT64)
OPTIONS(
  description="Taobao/Tmall manual order feed. v2: de-duplicates core_product on product_code before joining, fixing a 4.03x row fan-out present in v1. Output contract unchanged.")
AS
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
,base_order_daily AS (
SELECT
   o.o_id AS order_id
  ,o.so_id
  ,o.vn_order_date AS order_date
  ,o.product_code
  ,p.product_name
  ,o.items_sku_id AS variation_code
  ,v.variation_attributes
  ,p.product_launch_date
  ,o.items_base_price * 3800 AS retail_price          -- NOTE: hardcoded FX 3800 VND/CNY
  ,IFNULL(p.is_sale_end, 0) AS is_sale_end
  ,'Sale Ecommerce' AS order_sources_name
  ,CASE WHEN o.shop_id = 20209463 THEN 'Taobao'
        WHEN o.shop_id = 20209689 THEN 'Tmall' END AS channel
  ,'TQ Ecommerce' AS sale_channel
  ,CASE WHEN o.shop_id = 20209463 THEN 'Taobao'
        WHEN o.shop_id = 20209689 THEN 'Tmall' END AS sale_channel_details
  ,o.buyer_account
  ,o.platform_site
  ,'76be7836-6dc5-4b1c-9e48-b18e43127453' AS warehouse_id
  ,'Kho Trung Quốc (Back-up)' AS warehouse_name
  ,CASE 
            WHEN items_buyer_paid_amount <= 0 THEN 1
            WHEN TRIM(o.items_status) LIKE 'Cancelled' THEN 1
            WHEN (shop_id = 20209463 AND items_refund_qty > 0) THEN 1
            WHEN LEFT(items_sku_id,2) IN ('TG','HT','HN','HH','TD','TU') THEN 1
        ELSE 0
        END AS to_remove_record
  ,o.items_qty AS units_sold
  ,o.items_base_price               AS sale_revenue_cn
  ,o.items_buyer_paid_amount        AS revenue_cn
  ,o.items_buyer_paid_amount * 3800 AS revenue_vn
FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual` AS o
LEFT JOIN dim_product p
  ON o.product_code = p.product_code
LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v
  ON o.items_sku_id = v.variation_display_id
WHERE 1=1
  AND DATE_TRUNC(o.vn_order_date, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
  AND o.shop_id IN (20209463, 20209689)
)
SELECT
* EXCEPT (to_remove_record)
FROM base_order_daily
WHERE 1=1
  AND to_remove_record = 0;
