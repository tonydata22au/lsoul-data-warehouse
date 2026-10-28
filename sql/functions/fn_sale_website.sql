CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_sale_website(number_year_back INT64)
AS
WITH CTE AS (
SELECT
      o.increment_id AS order_id,
      o.created_at AS order_date,
      o.updated_at,
      CASE WHEN o.state <> o.status THEN CONCAT(o.state,'/',o.status) ELSE o.status END AS status,
      'Website' AS order_sources_name,
      'VN Online' AS sale_channel,
      o.store_name AS sale_channel_details,
      billing_address_country_id AS country_code,
      billing_address_city AS city,
      customer_email,
      CASE WHEN customer_is_guest = 1 THEN 'Yes' ELSE 'No' END AS customer_is_guest,
      o.order_currency_code,
      grand_total AS original_sales_revenue,
      CASE
          WHEN o.order_currency_code = 'USD' THEN grand_total * 26000
          WHEN o.order_currency_code = 'THB' THEN grand_total * 800
          WHEN o.order_currency_code = 'CNY' THEN grand_total * 3800
          ELSE grand_total
        END AS sales_revenue_vn,
      CASE WHEN COUNT(oi.items_sku) OVER (PARTITION BY oi.items_sku, o.increment_id ORDER BY o.increment_id) > 1 AND retail_price_incl_tax IS NULL THEN 1 ELSE 0 END AS remove_duplicate,
      oi.item_discount_amount,
      oi.qty_ordered,
      CASE WHEN LEFT(oi.items_sku,2) NOT IN ('TG','HT','HN','HH','TD','TU') THEN oi.items_sku END AS product
      
      
    FROM `marine-cycle-484213-b4.magento.core_magento_order` AS o
    JOIN `marine-cycle-484213-b4.magento.core_magento_order_item` AS oi ON o.entity_id = oi.entity_id
    WHERE 1=1
      AND DATE_TRUNC(o.created_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL number_year_back YEAR)
      --AND DATE_TRUNC(o.created_at, day) between '2025-11-01' and '2025-11-30'
      --AND oi.total_amount > 0
      
)
SELECT
order_id,
order_date,
updated_at,
status,
order_sources_name,
sale_channel,
sale_channel_details,
country_code,
city,
customer_email,
customer_is_guest,
order_currency_code,
original_sales_revenue,
sales_revenue_vn,
SUM(item_discount_amount) AS discount_amount,
COUNT(DISTINCT product) AS no_products,
SUM(qty_ordered) AS units_sold
FROM CTE
WHERE remove_duplicate = 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
order by 1 desc, 3 desc;
