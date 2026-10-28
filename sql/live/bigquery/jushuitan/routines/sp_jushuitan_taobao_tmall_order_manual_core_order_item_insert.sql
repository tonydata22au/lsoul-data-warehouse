CREATE PROCEDURE `marine-cycle-484213-b4`.jushuitan.sp_jushuitan_taobao_tmall_order_manual_core_order_item_insert()
BEGIN
/*
Author: Toan Pham
Date: 07/08/2026
Comment: This store procedure is to insert the data from stg_jushuitan_taobao_tmall_order_manual-> core_jushuitan_taobao_tmall_order_manual
Run syntax: 
  CALL `marine-cycle-484213-b4.jushuitan.sp_jushuitan_taobao_tmall_order_manual_core_order_item_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_taobao_tmall_order_manual`);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual` WHERE o_id IN (SELECT DISTINCT o_id
                                                                                FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_taobao_tmall_order_manual`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual`
  (
  proc_date,
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
)
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
WHERE DATE(proc_date) = data_proc_date
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
  items_refund_amount;
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'vn_order_date'
  ,'vn_order_date'
  ,30
  ,'jushuitan'
  ,'core_jushuitan_taobao_tmall_order_manual'
  ,'sp_jushuitan_taobao_tmall_order_manual_core_order_item_insert'
  ,'jushuitan'
  ,'marine-cycle-484213-b4.jushuitan.stg_jushuitan_taobao_tmall_order_manual'
  ,'marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual'
  ,'marine-cycle-484213-b4.jushuitan.sp_jushuitan_taobao_tmall_order_manual_core_order_item_insert'
  ,'marine-cycle-484213-b4.jushuitan.raw_jushuitan_taobao_tmall_order_manual'
);

  ELSE 
 
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'vn_order_date'
  ,'vn_order_date'
  ,30
  ,'jushuitan'
  ,'core_jushuitan_taobao_tmall_order_manual'
  ,'sp_jushuitan_taobao_tmall_order_manual_core_order_item_insert'
  ,'jushuitan'
  ,'marine-cycle-484213-b4.jushuitan.stg_jushuitan_taobao_tmall_order_manual'
  ,'marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual'
  ,'marine-cycle-484213-b4.jushuitan.sp_jushuitan_taobao_tmall_order_manual_core_order_item_insert'
  ,'marine-cycle-484213-b4.jushuitan.raw_jushuitan_taobao_tmall_order_manual'
  );

  END IF;
END;
