CREATE TABLE `marine-cycle-484213-b4.surfosm.stg_surfosm_order_return`
(
  proc_date TIMESTAMP,
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
  returns_detail_item_item_sku STRING,
  returns_detail_item_item_code STRING,
  returns_detail_item_i_name STRING,
  returns_detail_item_lot_number STRING,
  returns_detail_item_item_quantity INT64,
  returns_detail_item_status_item STRING
)
PARTITION BY DATE(proc_date);
