CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_wholeshale_vn(number_year_back INT64)
AS
SELECT
      o.order_id,
      order_date,
      status_name,
      CASE WHEN order_sources_name LIKE 'Wholesale' THEN 'Wholesales' ELSE order_sources_name END AS order_sources_name,
      'VN Wholesales' AS sale_channel,
      o.warehouse_name,
      assigning_seller_name,
      creator_name,
      COUNT(DISTINCT oi.order_id) AS total_orders,
      COUNT(DISTINCT oi.product_id) AS total_products,
      SUM(oi.cart_quantity) AS total_units_sold,
      SUM(oi.sales_revenue) AS sales_revenue,
      SUM(oi.item_total_discount) AS item_total_discount,
      customer_id,
      advanced_platform_fee_marketplace_voucher,
      total_discount,
      is_exchange_order,
      exchange_value,
      SUM(oi.sales_revenue) - SUM(item_total_discount) + advanced_platform_fee_marketplace_voucher - total_discount  AS revenue,
    FROM `marine-cycle-484213-b4.core_pancake.core_order_item` AS oi
    JOIN `marine-cycle-484213-b4.core_pancake.core_order` AS o
      ON oi.order_id = o.order_id
    WHERE 1=1
      --AND DATE_TRUNC(o.inserted_at, YEAR) >='2026-01-01' 
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.inserted_at, day) between '2025-11-01' and '2025-11-30'
      --AND o.order_id = 'REDACTED_EXAMPLE'
      AND o.order_id NOT IN (SELECT CAST(order_id AS STRING) FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` WHERE is_duplicate = 1)
      AND oi.cart_quantity > 0
      AND o.total_price > 0
      AND status_name NOT IN ('canceled','returned')
      AND o.order_sources_name LIKE ('Wholesale')
      GROUP BY 1, 2, 3, 4, 5, 6, 7,8, customer_id, exchange_value, advanced_platform_fee_marketplace_voucher, total_discount, is_exchange_order, total_price_after_sub_discount
      order by 1, 2, 5, 4;
