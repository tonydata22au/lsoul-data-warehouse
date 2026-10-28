--truncate table `marine-cycle-484213-b4.magento.core_magento_order_item`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.magento.core_magento_order_item`
PARTITION BY DATE(updated_at)
CLUSTER BY increment_id, entity_id,items_sku,items_name
OPTIONS (
  require_partition_filter=false
) AS
SELECT
created_at,
MAX(updated_at) AS updated_at,
increment_id,
entity_id,
order_currency_code,
state, 
status,
item_id,
product_id,
parent_item_id,
items_sku,
items_name,
is_free_shipping,
qty_ordered,
qty_canceled,
qty_refunded,
qty_shipped,
no_discount,
discount_percent,
amount_refunded,
item_discount_amount,
original_price,
retail_price,
retail_price_incl_tax,
tax_amount,
tax_percent,
total_amount_incl_tax,
total_amount
FROM `marine-cycle-484213-b4.magento.stg_magento_order`
WHERE proc_date = '2026-07-04'
GROUP BY
created_at,
increment_id,
entity_id,
order_currency_code,
state,
status,
item_id,
product_id,
parent_item_id,
items_sku,
items_name,
is_free_shipping,
qty_ordered,
qty_canceled,
qty_refunded,
qty_shipped,
no_discount,
discount_percent,
amount_refunded,
item_discount_amount,
original_price,
retail_price,
retail_price_incl_tax,
tax_amount,
tax_percent,
total_amount_incl_tax,
total_amount