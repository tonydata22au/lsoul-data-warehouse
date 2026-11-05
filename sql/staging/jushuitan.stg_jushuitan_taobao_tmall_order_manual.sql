--truncate table `marine-cycle-484213-b4.jushuitan.stg_jushuitan_taobao_tmall_order_manual`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.jushuitan.stg_jushuitan_taobao_tmall_order_manual`
PARTITION BY DATE(proc_date)
OPTIONS (
  require_partition_filter=false
) AS
SELECT
  TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) AS proc_date,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', order_date))  AS order_date,
  DATETIME(PARSE_TIMESTAMP('%Y%m%d%H%M%S', vn_order_date))  AS vn_order_date,
  SAFE_CAST(o_id AS INT64) AS o_id,
  oo_id,
  SAFE_CAST(shop_id AS NUMERIC) AS shop_id,
  shop_name,
  shop_account_no,
  buyer_account,
  payment_date,
  SAFE_CAST(freights AS NUMERIC) AS freights,
  shop_status,
  platform_site,
  SAFE_CAST(so_id AS NUMERIC) AS so_id,
  raw_oo_id,
  product_code,
  items_sku_id,
  SAFE_CAST(items_qty AS NUMERIC) AS items_qty,
  SAFE_CAST(items_price AS NUMERIC) AS items_price,
  SAFE_CAST(items_amount AS NUMERIC) AS items_amount,
  SAFE_CAST(items_base_price AS NUMERIC) AS items_base_price,
  items_status,
  items_category,
  items_group_name,
  items_raw_sku_id,
  items_refund_status,
  SAFE_CAST(items_buyer_paid_amount AS NUMERIC) AS items_buyer_paid_amount,
  SAFE_CAST(items_registered_qty AS NUMERIC) AS items_registered_qty,
  SAFE_CAST(items_refund_qty AS NUMERIC) AS items_refund_qty,
  SAFE_CAST(items_refund_amount AS NUMERIC) AS items_refund_amount

FROM `marine-cycle-484213-b4.jushuitan.raw_jushuitan_taobao_tmall_order_manual`
WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2026-08-07")