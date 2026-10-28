CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4`.jushuitan.sp_jushuitan_core_order_item_insert()
BEGIN
/*
Author: Toan Pham
Date: 09/05/2026
Comment: This store procedure is to insert the data from stg_jushuitan_order -> core_jushuitan_order_item
Run syntax: 
  CALL `marine-cycle-484213-b4.jushuitan.sp_jushuitan_core_order_item_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`);

  DECLARE data_insert_to_date DATE DEFAULT
                                              (SELECT MAX(DATE(inserted_at)) 
                                              FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`
                                              WHERE DATE(proc_date) = data_proc_date);
  DECLARE data_insert_from_date DATE DEFAULT
                                              (SELECT MIN(DATE(inserted_at))
                                              FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`
                                              WHERE DATE(proc_date) = data_proc_date);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item` WHERE o_id IN (SELECT DISTINCT o_id
                                                                                FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_order`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item`
  (
 ts,
inserted_at,
o_id,
order_date,
vn_order_date,
so_id,
raw_so_id,
items_oi_id,
product_code,
product_launch_date,
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
)
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
WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
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
items_send_warehouse;
  
  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'jushuitan'
            ,'core_jushuitan_order_item'
            ,1
            ,1
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_jushuitan_core_order_item_insert'
            ,'jushuitan'
            ,'marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item'
            ,'marine-cycle-484213-b4.jushuitan.sp_jushuitan_core_order_item_insert'
          );

  ELSE 

  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'jushuitan'
            ,'core_jushuitan_order_item'
            ,0
            ,0
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_jushuitan_core_order_item_insert'
            ,'jushuitan'
            ,'marine-cycle-484213-b4.jushuitan.core_jushuitan_order_item'
            ,'marine-cycle-484213-b4.jushuitan.sp_jushuitan_core_order_item_insert'
          );
  END IF;
END;
