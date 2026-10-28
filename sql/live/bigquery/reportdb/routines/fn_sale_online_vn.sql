CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_online_vn(number_year_back INT64)
AS
SELECT
      o.order_id,
      order_date,
      status_name,
      order_sources_name,
      'VN Online' AS sale_channel,
      oi.warehouse_id,
      o.warehouse_name,
      customer_id,
      COUNT(DISTINCT oi.order_id) AS total_orders,
      COUNT(DISTINCT CASE WHEN LEFT(p.product_code,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.product_id END) AS total_products,
      SUM(CASE WHEN LEFT(p.product_code,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.cart_quantity ELSE 0 END) AS total_units_sold,
      SUM(oi.sales_revenue) AS sales_revenue, --Doanh so ban hang
      SUM(oi.item_total_discount) AS item_total_discount,
      SUM(oi.sales_revenue) - SUM(item_total_discount) + advanced_platform_fee_marketplace_voucher - total_discount  AS revenue
      -- advanced_platform_fee_marketplace_voucher,
      -- total_discount,
      -- is_exchange_order,
      -- exchange_value,
      -- assigning_seller_name,
      -- creator_name
    FROM `marine-cycle-484213-b4.core_pancake.core_order_item` AS oi
    JOIN `marine-cycle-484213-b4.core_pancake.core_order` AS o ON oi.order_id = o.order_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_product` AS p ON oi.product_id = p.raw_product_id
    WHERE 1=1
      AND DATE_TRUNC(o.inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.inserted_at, day) between '2026-05-01' and '2026-05-01'
      --AND o.order_id = 'REDACTED_EXAMPLE'
      AND o.order_id NOT IN (SELECT CAST(order_id AS STRING) FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned` WHERE is_duplicate = 1)
      AND status_name NOT IN ('canceled','returned','packing')
      AND o.order_sources_name NOT LIKE ('Wholesale')
      AND (
          assigning_seller_name IN ('OANHONLINE','TLINHONLINE','TAIONLINE', 'TRAM XLD', 'Bao Tran XLD') 
          OR creator_name IN ('QUINT','OANHONLINE','TLINHONLINE','TAIONLINE', 'TRAM XLD', 'Bao Tran XLD'))
      AND (o.order_sources_name IN ('Website', 'Facebook', 'Webcake', 'Instagram', 'Zalo') OR o.warehouse_name = 'Kho Online')
      GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, customer_id, exchange_value, advanced_platform_fee_marketplace_voucher, total_discount, is_exchange_order, total_price_after_sub_discount
      order by 1, 2, 5, 4;
