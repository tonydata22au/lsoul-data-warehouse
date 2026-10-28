--truncate table `marine-cycle-484213-b4.surfosm.core_surfosm_order_return`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.surfosm.core_surfosm_order_return`
PARTITION BY parameter_date
CLUSTER BY  parameter_date,order_number,channel,returned_product_code
OPTIONS (
  require_partition_filter=false
) AS
SELECT DISTINCT
parameter_date,
order_number,
external_order_id,
channel,
shipping,
total_returns,
returns_return_document_code,
returns_order_number,
returns_type_cancel,
returns_qty,
returns_received,
returns_status,
IFNULL(returns_detail_item_item_sku,returns_detail_item_item_code) AS returned_product_sku,
REGEXP_EXTRACT(returns_detail_item_item_code, r'^([^-]+)') AS returned_product_code,
returns_detail_item_i_name AS returned_product_name,
returns_detail_item_lot_number AS returned_product_lot_number,
returns_detail_item_item_quantity AS returned_product_quantity,
returns_detail_item_status_item AS returned_product_status
FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order_return`
WHERE DATE(proc_date) >= "2026-04-25"
