CREATE TABLE `marine-cycle-484213-b4.surfosm.raw_surfosm_order_return`
(
  parameter_date STRING,
  order_number STRING,
  external_order_id STRING,
  channel STRING,
  shipping STRING,
  total_returns STRING,
  returns_return_document_code STRING,
  returns_order_number STRING,
  returns_type_cancel STRING,
  returns_qty STRING,
  returns_received STRING,
  returns_status STRING,
  returns_detail_item_item_sku STRING,
  returns_detail_item_item_code STRING,
  returns_detail_item_i_name STRING,
  returns_detail_item_lot_number STRING,
  returns_detail_item_item_quantity STRING,
  returns_detail_item_status_item STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
