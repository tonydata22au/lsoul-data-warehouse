--truncate table `marine-cycle-484213-b4.surfosm.core_surfosm_order_item`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.surfosm.core_surfosm_order_item`
PARTITION BY DATE(inserted_at)
CLUSTER BY  parameter_date,order_number,product_sku,product_code
OPTIONS (
  require_partition_filter=false
) AS
SELECT DISTINCT
  parameter_date,
  inserted_at,
  order_number,
  external_order_id,
  IFNULL(order_items_item_sku,order_items_item_code) AS product_sku,
  REGEXP_EXTRACT(order_items_item_code, r'^([^-]+)') AS product_code,
   DATE(
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(order_items_item_code, r'\d{6}'), 1, 2) AS INT64) + 2000,
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(order_items_item_code, r'\d{6}'), 3, 2) AS INT64),
    01
    ) product_launch_date,
  order_items_item_name AS product_name,
  order_items_item_qty AS product_qty,
  order_items_item_cancelled_qty AS cancelled_qty, 
  order_items_item_returned_qty AS returned_qty,
  order_items_item_effective_qty AS effective_qty, 
  order_items_item_adjusted_total AS adjusted_total,
  order_items_selling_price * order_items_item_qty AS selling_price,
  order_items_original_price * order_items_item_qty AS original_price,
  order_items_paid_price * order_items_item_qty AS paid_price,
  order_items_discount_platform  AS discount_platform,
  order_items_discount_seller AS discount_seller,
  IFNULL(order_items_shipped_item_sku,order_items_shipped_item_code) AS shipped_product_sku,
  REGEXP_EXTRACT(order_items_shipped_item_code, r'^([^-]+)') AS shipped_product_code,
  order_items_shipped_item_name AS shipped_product_name,
  order_items_shipped_item_qty AS shipped_qty,
  order_items_shipped_item_cancelled_qty AS shipped_cancelled_qty,
  order_items_shipped_item_returned_qty AS shipped_returned_qty,
  order_items_shipped_item_effective_qty AS shipped_effective_qty, 
  order_items_shipped_item_adjusted_total AS shipped_adjusted_total,
  order_items_shipped_item_cost AS shipped_cost,
  order_items_shipped_item_selling AS shipped_product_selling_price
FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`
WHERE DATE(proc_date) = "2026-08-21"