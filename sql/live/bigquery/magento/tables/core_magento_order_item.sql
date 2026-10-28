CREATE TABLE `marine-cycle-484213-b4.magento.core_magento_order_item`
(
  created_at DATETIME,
  updated_at DATETIME,
  increment_id STRING,
  entity_id INT64,
  order_currency_code STRING,
  state STRING,
  status STRING,
  item_id INT64,
  product_id INT64,
  parent_item_id INT64,
  items_sku STRING,
  items_name STRING,
  is_free_shipping INT64,
  qty_ordered NUMERIC,
  qty_canceled NUMERIC,
  qty_refunded NUMERIC,
  qty_shipped NUMERIC,
  no_discount NUMERIC,
  discount_percent FLOAT64,
  amount_refunded FLOAT64,
  item_discount_amount FLOAT64,
  original_price FLOAT64,
  retail_price FLOAT64,
  retail_price_incl_tax FLOAT64,
  tax_amount FLOAT64,
  tax_percent FLOAT64,
  total_amount_incl_tax FLOAT64,
  total_amount FLOAT64
)
PARTITION BY DATE(updated_at)
CLUSTER BY increment_id, entity_id, items_sku, items_name;
