--truncate table `marine-cycle-484213-b4.surfosm.stg_surfosm_order_return`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.surfosm.stg_surfosm_order_return`
PARTITION BY DATE(proc_date)
OPTIONS (
  require_partition_filter=false
) AS
SELECT
TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
SAFE_CAST(parameter_date AS DATE) AS parameter_date,
order_number, 
external_order_id, 
channel, 
shipping, 
SAFE_CAST(total_returns AS INT64) AS total_returns,
returns_return_document_code,
returns_order_number,
returns_type_cancel,
SAFE_CAST(returns_qty AS INT64) AS returns_qty,
SAFE_CAST(returns_received AS INT64) AS returns_received,
returns_status,
returns_detail_item_item_sku,
returns_detail_item_item_code,
returns_detail_item_i_name,
returns_detail_item_lot_number,
SAFE_CAST(returns_detail_item_item_quantity AS INT64) AS returns_detail_item_item_quantity,
returns_detail_item_status_item
FROM `marine-cycle-484213-b4.surfosm.raw_surfosm_order_return`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-04-25")

