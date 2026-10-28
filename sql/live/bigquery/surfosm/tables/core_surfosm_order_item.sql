CREATE TABLE `marine-cycle-484213-b4.surfosm.core_surfosm_order_item`
(
  parameter_date DATE,
  inserted_at DATETIME,
  order_number STRING,
  external_order_id STRING,
  product_sku STRING,
  product_code STRING,
  product_launch_date DATE,
  product_name STRING,
  product_qty FLOAT64,
  cancelled_qty FLOAT64,
  returned_qty FLOAT64,
  effective_qty FLOAT64,
  adjusted_total FLOAT64,
  selling_price FLOAT64,
  original_price FLOAT64,
  paid_price FLOAT64,
  discount_platform FLOAT64,
  discount_seller FLOAT64,
  shipped_product_sku STRING,
  shipped_product_code STRING,
  shipped_product_name STRING,
  shipped_qty NUMERIC,
  shipped_cancelled_qty NUMERIC,
  shipped_returned_qty NUMERIC,
  shipped_effective_qty NUMERIC,
  shipped_adjusted_total NUMERIC,
  shipped_cost FLOAT64,
  shipped_product_selling_price FLOAT64
)
PARTITION BY DATE(inserted_at)
CLUSTER BY parameter_date, order_number, product_sku, product_code;
