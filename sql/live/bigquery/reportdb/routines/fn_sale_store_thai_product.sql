CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_store_thai_product(number_year_back INT64)
AS
SELECT DISTINCT
      oi.order_id,
      order_date,
      oi.product_id,
      p.product_code,
      oi.product_name,
      v.variation_display_id AS variation_code,
      v.variation_attributes,
      p.product_launch_date,
      oi.retail_price * 8 AS retail_price,
      CASE WHEN TRIM(UPPER(p.product_tags)) = 'SYS_01_SALE_END' THEN 1 ELSE 0 END is_sale_end,
      oi.cart_quantity AS units_sold,
      oi.sales_revenue       AS sales_revenue_thai,
      oi.sales_revenue * 8      AS sales_revenue_vn,  
      oi.item_total_discount AS item_total_discount_thai,
      ROUND(SAFE_DIVIDE(
                      (advanced_platform_fee_marketplace_voucher  - total_discount )
                      ,SUM(oi.cart_quantity) OVER (PARTITION BY o.order_id ORDER BY o.order_id)
                      ),0) 
      AS extra_sale_revenue_thai,
      sales_revenue
      + item_total_discount
      +  ROUND(SAFE_DIVIDE(
                      (advanced_platform_fee_marketplace_voucher - total_discount)
                      ,SUM(oi.cart_quantity) OVER (PARTITION BY o.order_id ORDER BY o.order_id)
                      ),0) 
      AS revenue_thai,
      ROUND(SAFE_DIVIDE(
                      (advanced_platform_fee_marketplace_voucher * 8 - total_discount * 8)
                      ,SUM(oi.cart_quantity) OVER (PARTITION BY o.order_id ORDER BY o.order_id)
                      ),0) 
      AS extra_sale_revenue_vn,
      sales_revenue * 8
        + item_total_discount * 8
        +  ROUND(SAFE_DIVIDE(
                        (advanced_platform_fee_marketplace_voucher * 8 - total_discount * 8)
                        ,SUM(oi.cart_quantity) OVER (PARTITION BY o.order_id ORDER BY o.order_id)
                        ),0) 
      AS revenue_vn,
      CASE WHEN o.warehouse_name IN ('Kho Emsphere','Central Ladprao','Kho Central World') THEN 'Store' ELSE  o.warehouse_name END AS order_sources_name,
      'TL Offline Store' AS sale_channel,
      CASE 
          WHEN TRIM(UPPER(o.warehouse_name)) LIKE '%EMSPHERE%' THEN 'Emsphere'
          WHEN TRIM(UPPER(o.warehouse_name)) LIKE '%CENTRAL LADPRAO%' THEN 'Central Ladprao'
          WHEN TRIM(UPPER(o.warehouse_name)) LIKE '%CENTRAL WORLD%' THEN 'Central World'
      ELSE o.warehouse_name 
      END AS sale_channel_details,
      CASE 
        WHEN tags LIKE '%Facebook%'   THEN 'Facebook'
        WHEN tags LIKE '%Instagram%'  THEN 'Instagram'
        WHEN tags LIKE '%Tiktok%'     THEN 'Tiktok'
        WHEN tags LIKE '%Website%' OR  tags LIKE '%Google%' THEN 'Online Ads'
        WHEN tags LIKE '%Shopee%'     THEN 'Shopee'
        WHEN tags LIKE '%XIAO%'       THEN 'Xiaohongshu'
       ELSE 'N/A'
      END AS customer_from_ads_source,
      oi.warehouse_id,
      o.warehouse_name,
      customer_id,
      is_exchange_order,
      exchange_value  AS exchange_value_thai,
      exchange_value * 8 AS exchange_value_vn,
      --assigning_seller_name,
      --creator_name,
    FROM `marine-cycle-484213-b4.core_pancake.core_order` AS o 
    JOIN  `marine-cycle-484213-b4.core_pancake.core_order_item` AS oi ON oi.order_id = o.order_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_id = p.raw_product_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_variations` AS v ON oi.variation_id = v.variation_id
    WHERE 1=1
      --AND DATE_TRUNC(o.inserted_at, YEAR) >='2026-01-01' 
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.inserted_at, day) between '2025-11-01' and '2025-11-30'
      --AND o.order_id = 'REDACTED_EXAMPLE'
      AND o.order_id NOT IN (SELECT CAST(order_id AS STRING) FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` WHERE is_duplicate = 1)
      AND oi.cart_quantity > 0
      AND o.total_price > 0
      AND status_name NOT IN ('canceled','returned')
      AND o.order_sources_name NOT LIKE ('Wholesale')
      AND o.order_sources_name IN (null,'') 
      AND is_received_at_shop = 1 
      AND o.warehouse_name IN ('Kho Emsphere','Central Ladprao','Kho Central World')
      AND LEFT(variation_display_id,2) NOT IN ('TG','HT','HN','HH','TD','TU')
      -- AND o.warehouse_name NOT IN (
      -- 'Kho Marketing'
      -- ,'Kho MKT Thailand'
      -- ,'Kho Tổng 480F'
      -- ,'Kho Thái (Back-up)'
      -- ,'Kho Trung Quốc (Back-up)'
      -- ,'Kho Nguyễn Trãi'
      -- ,'Kho Offfice Thailand'
      -- ,'Kho Ecommerce Việt Nam'
      -- )
       order by 2 desc, 4, 5;
