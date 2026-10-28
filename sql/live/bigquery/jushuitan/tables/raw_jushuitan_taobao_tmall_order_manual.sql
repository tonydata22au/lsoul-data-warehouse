CREATE TABLE `marine-cycle-484213-b4.jushuitan.raw_jushuitan_taobao_tmall_order_manual`
(
  o_id STRING,
  oo_id STRING,
  shop_id STRING,
  shop_name STRING,
  shop_account_no STRING,
  buyer_account STRING,
  order_date STRING,
  vn_order_date STRING,
  payment_date STRING,
  freights STRING,
  shop_status STRING,
  platform_site STRING,
  so_id STRING,
  raw_oo_id STRING,
  product_code STRING,
  items_sku_id STRING,
  items_qty STRING,
  items_price STRING,
  items_amount STRING,
  items_base_price STRING,
  items_status STRING,
  items_category STRING,
  items_group_name STRING,
  items_raw_sku_id STRING,
  items_refund_status STRING,
  items_buyer_paid_amount STRING,
  items_registered_qty STRING,
  items_refund_qty STRING,
  items_refund_amount STRING
)
PARTITION BY DATE(_PARTITIONTIME)
OPTIONS(
  require_partition_filter=true
);
