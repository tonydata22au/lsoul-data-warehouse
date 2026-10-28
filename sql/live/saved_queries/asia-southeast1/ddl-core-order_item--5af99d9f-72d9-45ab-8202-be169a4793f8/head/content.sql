--truncate table `marine-cycle-484213-b4.core_pancake.core_order_item`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_pancake.core_order_item`
PARTITION BY DATE(order_date)
CLUSTER BY  order_id ,product_id,variation_id
AS
SELECT
order_item_id,
inserted_at AS order_date,
MAX(updated_at) AS updated_at,
order_id,
system_id,
product_id,
product_name,
variation_id,
cart_quantity,
is_discount_percent,
unit_discount,
item_total_discount,
exact_price AS line_total,
retail_price,
retail_price * cart_quantity AS sales_revenue,
original_retail_price,
last_import_price,
average_price,
quantity_ordered,
quantity_returned,
quantity_returning,
return_count,
exchange_count,
is_wholesale,
is_one_time_product,
warehouse_id,
warehouse_name
FROM `marine-cycle-484213-b4.stg_pancake.stg_order`
WHERE DATE(proc_date) >= "2026-06-22"
GROUP BY
order_item_id,
order_date,
order_id,
system_id,
product_id,
product_name,
variation_id,
cart_quantity,
is_discount_percent,
unit_discount,
item_total_discount,
line_total,
retail_price,
sales_revenue,
original_retail_price,
last_import_price,
average_price,
quantity_ordered,
quantity_returned,
quantity_returning,
return_count,
exchange_count,
is_wholesale,
is_one_time_product,
warehouse_id,
warehouse_name;

