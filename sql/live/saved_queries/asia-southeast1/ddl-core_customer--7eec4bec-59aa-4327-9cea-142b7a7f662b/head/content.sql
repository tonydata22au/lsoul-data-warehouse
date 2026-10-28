--DROP TABLE `marine-cycle-484213-b4.core_pancake.core_customer`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_pancake.core_customer`
PARTITION BY DATE(updated_at)
CLUSTER BY  customer_id,order_sources, last_order_at
AS
SELECT
inserted_at,
MAX(updated_at) AS updated_at,
customer_id,
username,
tags,
fb_id,
is_block,
assigned_user_id,
creator_name,
creator_id,
currency,
order_count,
succeed_order_count,
returned_order_count,
purchased_amount,
last_order_at,
order_sources,
shop_customer_addresses_id,
shop_customer_addresses_country_code,
shop_customer_addresses_province_id,
shop_customer_addresses_commune_id
FROM `marine-cycle-484213-b4.stg_pancake.stg_customer`
WHERE proc_date >= "2010-01-01"
GROUP BY
inserted_at,
customer_id,
username,
tags,
fb_id,
is_block,
assigned_user_id,
creator_name,
creator_id,
currency,
order_count,
succeed_order_count,
returned_order_count,
purchased_amount,
last_order_at,
order_sources,
shop_customer_addresses_id,
shop_customer_addresses_country_code,
shop_customer_addresses_province_id,
shop_customer_addresses_commune_id;