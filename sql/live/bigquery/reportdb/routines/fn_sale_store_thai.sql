CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_store_thai(number_year_back INT64)
AS
SELECT
      o.order_id,
      order_date,
      status_name,
      CASE 
        WHEN o.warehouse_name IN ('Kho Emsphere','Central Ladprao','Kho Central World') 
        THEN 'Store' 
        ELSE  o.warehouse_name 
        END AS order_sources_name,
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
      COUNT(DISTINCT oi.order_id) AS total_orders,
      COUNT(DISTINCT CASE WHEN LEFT(p.product_code,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.product_id END) AS total_products,
      SUM(CASE WHEN LEFT(p.product_code,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.cart_quantity ELSE 0 END) AS total_units_sold,
      SUM(oi.sales_revenue ) AS sales_revenue_thai,
      SUM(oi.sales_revenue * 8) AS sales_revenue_vn,
      SUM(oi.item_total_discount) AS item_total_discount_thai,
      SUM(oi.sales_revenue) - SUM(item_total_discount) + advanced_platform_fee_marketplace_voucher - total_discount AS revenue_thai,
      SUM(oi.sales_revenue * 8) - SUM(item_total_discount * 8) + advanced_platform_fee_marketplace_voucher * 8 - total_discount * 8 AS revenue_vn,
      --assigning_seller_name,
      --creator_name,
    FROM `marine-cycle-484213-b4.core_pancake.core_order_item` AS oi
    JOIN `marine-cycle-484213-b4.core_pancake.core_order` AS o ON oi.order_id = o.order_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_id = p.raw_product_id
    WHERE 1=1
      --AND DATE_TRUNC(o.inserted_at, YEAR) >='2026-01-01' 
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.inserted_at, day) between '2025-11-01' and '2025-11-30'
      --AND o.order_id = 'REDACTED_EXAMPLE'
      AND o.order_id NOT IN (SELECT CAST(order_id AS STRING) FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` WHERE is_duplicate = 1)
      AND oi.cart_quantity > 0
      AND o.total_price > 0
      AND status_name NOT IN ('cancelled','returned')
      AND o.order_sources_name NOT LIKE ('Wholesale')
      AND o.order_sources_name IN (null,'') 
      AND is_received_at_shop = 1 
      AND o.warehouse_name IN ('Kho Emsphere','Central Ladprao','Kho Central World')
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
      GROUP BY 1, 2, 3, 4, 5, 6, 7,8, 9, 10,11,12,13,advanced_platform_fee_marketplace_voucher,total_discount
      order by 2 DESC ,4, 5;
