--drop table `marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item`
PARTITION BY DATE(vn_order_date)
CLUSTER BY  ts, o_id, vn_order_date
OPTIONS (
  require_partition_filter=false
) AS
SELECT
ts,
MAX(inserted_at) AS inserted_at,
o_id,
order_date,
vn_order_date,
so_id,
raw_so_id,
items_oi_id,
CASE 
    WHEN LENGTH(REGEXP_EXTRACT(items_id, r'^([^-]+)')) <= 10 
      THEN REGEXP_EXTRACT(items_id, r'^([^-]+)')
    WHEN LENGTH(REGEXP_EXTRACT(items_id, r'^([^-]+)')) > 10 AND LENGTH(REGEXP_EXTRACT(items_sku_id, r'^([^-]+)')) <= 10  
      THEN REGEXP_EXTRACT(items_sku_id, r'^([^-]+)')
    ELSE REGEXP_EXTRACT(items_id, r'^([^-]+)')
    END AS product_code,
SAFE.DATE(
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(items_id, r'\d{6}'), 1, 2) AS INT64) + 2000,
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(items_id, r'\d{6}'), 3, 2) AS INT64),
    01
    ) product_launch_date,
items_sku_id,
items_name,
items_properties_value,
items_sku_type,
items_status,
items_qty,
items_price,
items_base_price,
items_amount,
items_buyer_paid_amount,
items_seller_income_amount,
items_discount_rate,
items_refund_status,
items_refund_qty,
items_refund_id,
items_is_gift,
items_is_presale,
items_remark,
items_item_ext_data,
items_il_id,
items_src_combine_sku_id,
items_bu_id,
items_send_warehouse,
items_shop_id,
items_raw_so_id

FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`
WHERE DATE(proc_date) >= "2026-05-09"
GROUP BY
ts,
order_date,
vn_order_date,
o_id,
so_id,
raw_so_id,
items_id,
items_oi_id,
items_outer_oi_id,
items_raw_so_id,
items_sku_id,
items_shop_id,
items_name,
items_properties_value,
items_sku_type,
items_status,
items_is_gift,
items_is_presale,
items_remark,
items_item_ext_data,
items_qty,
items_price,
items_base_price,
items_amount,
items_buyer_paid_amount,
items_seller_income_amount,
items_discount_rate,
items_refund_status,
items_refund_qty,
items_refund_id,
items_il_id,
items_src_combine_sku_id,
items_bu_id,
items_send_warehouse
