CREATE TABLE `marine-cycle-484213-b4.surfosm.core_surfosm_order_return`
(
  parameter_date DATE,
  order_number STRING,
  external_order_id STRING,
  channel STRING,
  shipping STRING,
  total_returns INT64,
  returns_return_document_code STRING,
  returns_order_number STRING,
  returns_type_cancel STRING,
  returns_qty INT64,
  returns_received INT64,
  returns_status STRING,
  returned_product_sku STRING,
  returned_product_code STRING,
  returned_product_name STRING,
  returned_product_lot_number STRING,
  returned_product_quantity INT64,
  returned_product_status STRING
)
PARTITION BY parameter_date
CLUSTER BY parameter_date, order_number, channel, returned_product_code;
