CREATE TABLE `marine-cycle-484213-b4.dev_core_pancake.core_order_item`
(
  order_item_id STRING OPTIONS(description="Pancake line-item identifier."),
  order_date DATETIME OPTIONS(description="Pancake order creation datetime in Asia/Ho_Chi_Minh local time; daily partition column."),
  updated_at STRING OPTIONS(description="Latest source updated_at STRING for the selected line item."),
  order_id STRING OPTIONS(description="Pancake order identifier."),
  system_id INT64 OPTIONS(description="System id from the supplied core_order_item DDL."),
  product_id STRING OPTIONS(description="Pancake item_product_id; kept as text. Surrounding whitespace is trimmed and blank values become NULL; case is preserved."),
  product_name STRING OPTIONS(description="Pancake item_variation_info.name; kept as text. Surrounding whitespace is trimmed and blank values become NULL; case is preserved."),
  variation_id STRING OPTIONS(description="Pancake item_variation_id; kept as text. Surrounding whitespace is trimmed and blank values become NULL; case is preserved."),
  cart_quantity INT64 OPTIONS(description="Pancake cart quantity. Whole-number strings are cast safely; invalid/fractional values become NULL."),
  is_discount_percent INT64 OPTIONS(description="Pancake is discount percent. Whole-number strings are cast safely; invalid/fractional values become NULL. 0 = false, 1 = true."),
  unit_discount FLOAT64 OPTIONS(description="Unit discount as FLOAT64 per the supplied core DDL."),
  item_total_discount INT64 OPTIONS(description="Item total discount as INT64 per the supplied core DDL; non-integer source values become NULL."),
  line_total FLOAT64 OPTIONS(description="Line total as FLOAT64 per the supplied core DDL."),
  retail_price FLOAT64 OPTIONS(description="Retail price as FLOAT64 per the supplied core DDL."),
  sales_revenue FLOAT64 OPTIONS(description="Sales revenue as FLOAT64 per the supplied core DDL."),
  original_retail_price FLOAT64 OPTIONS(description="Original retail price as FLOAT64 per the supplied core DDL."),
  last_import_price FLOAT64 OPTIONS(description="Last import price as FLOAT64 per the supplied core DDL."),
  average_price FLOAT64 OPTIONS(description="Average price as FLOAT64 per the supplied core DDL."),
  quantity_ordered INT64 OPTIONS(description="Pancake quantity ordered. Whole-number strings are cast safely; invalid/fractional values become NULL."),
  quantity_returned INT64 OPTIONS(description="Pancake quantity returned. Whole-number strings are cast safely; invalid/fractional values become NULL."),
  quantity_returning INT64 OPTIONS(description="Pancake quantity returning. Whole-number strings are cast safely; invalid/fractional values become NULL."),
  return_count INT64 OPTIONS(description="Pancake return count. Whole-number strings are cast safely; invalid/fractional values become NULL."),
  exchange_count INT64 OPTIONS(description="Pancake exchange count. Whole-number strings are cast safely; invalid/fractional values become NULL."),
  is_wholesale INT64 OPTIONS(description="Pancake is wholesale. Whole-number strings are cast safely; invalid/fractional values become NULL. 0 = false, 1 = true."),
  is_one_time_product INT64 OPTIONS(description="Pancake is one time product. Whole-number strings are cast safely; invalid/fractional values become NULL. 0 = false, 1 = true."),
  warehouse_id STRING OPTIONS(description="Warehouse id from the supplied core_order_item DDL."),
  warehouse_name STRING OPTIONS(description="Warehouse name from the supplied core_order_item DDL.")
)
PARTITION BY DATE(order_date)
CLUSTER BY order_id, product_id, variation_id
OPTIONS(
  description="One row per (order_id, order_item_id) in the rolling 30 complete business-date window. Matches the supplied core DDL, including line_total and sales_revenue."
);
