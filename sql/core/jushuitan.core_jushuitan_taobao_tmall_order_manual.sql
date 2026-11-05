--truncate table `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual`
PARTITION BY DATE(vn_order_date)
CLUSTER BY  o_id, vn_order_date
OPTIONS (
  require_partition_filter=false
) AS
SELECT
  MAX(proc_date) AS proc_date,
  o_id,
  order_date,
  vn_order_date,
  oo_id,
  shop_id,
  shop_name,
  shop_account_no,
  buyer_account,
  payment_date,
  freights,
  shop_status,
  platform_site,
  so_id,
  raw_oo_id,
  product_code,
  items_sku_id,
  items_qty,
  items_price,
  items_amount,
  items_base_price,
  CASE 
    WHEN items_status LIKE '发货后取消' THEN 'Cancelled' 
    WHEN items_status LIKE '取消' THEN 'Cancelled'
    ELSE items_status
    END AS items_status,
  items_category,
  items_group_name,
  items_raw_sku_id,
  CASE 
    WHEN items_refund_status LIKE '未申请退款' THEN ''
    WHEN items_refund_status LIKE '退款关闭' THEN 'closed'
    WHEN items_refund_status LIKE '等待退款' THEN 'waiting for refund'
    WHEN items_refund_status LIKE '成功退款' THEN 'success'
    ELSE items_refund_status
    END AS items_refund_status,
  items_buyer_paid_amount,
  items_registered_qty,
  items_refund_qty,
  items_refund_amount

FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_taobao_tmall_order_manual`
WHERE DATE(proc_date) = "2026-08-07"
GROUP BY 
  o_id,
  order_date,
  vn_order_date,
  oo_id,
  shop_id,
  shop_name,
  shop_account_no,
  buyer_account,
  payment_date,
  freights,
  shop_status,
  platform_site,
  so_id,
  raw_oo_id,
  product_code,
  items_sku_id,
  items_qty,
  items_price,
  items_amount,
  items_base_price,
  items_status,
  items_category,
  items_group_name,
  items_raw_sku_id,
  items_refund_status,
  items_buyer_paid_amount,
  items_registered_qty,
  items_refund_qty,
  items_refund_amount