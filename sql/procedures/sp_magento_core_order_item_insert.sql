CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.magento.sp_magento_core_order_item_insert`()
BEGIN
/*
Author: Toan Pham
Date: 05/07/2026
Comment: This store procedure is to insert the data from stg_magento_order -> core_magento_order_item
Run syntax: 
  CALL `marine-cycle-484213-b4.magento.sp_magento_core_order_item_insert`() --today date
*/

DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.magento.stg_magento_order`);

  DECLARE data_insert_to_date DATE DEFAULT
                                              (SELECT MAX(DATE(updated_at)) 
                                              FROM `marine-cycle-484213-b4.magento.stg_magento_order`
                                              WHERE DATE(proc_date) = data_proc_date);
  DECLARE data_insert_from_date DATE DEFAULT
                                              (SELECT MIN(DATE(updated_at))
                                              FROM `marine-cycle-484213-b4.magento.stg_magento_order`
                                              WHERE DATE(proc_date) = data_proc_date);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.magento.core_magento_order_item` WHERE entity_id IN (SELECT DISTINCT entity_id
                                                                                FROM `marine-cycle-484213-b4.magento.stg_magento_order`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.magento.core_magento_order_item`
  (
  created_at,
  updated_at,
  increment_id,
  entity_id,
  order_currency_code,
  state, 
  status,
  item_id,
  product_id,
  parent_item_id,
  items_sku,
  items_name,
  is_free_shipping,
  qty_ordered,
  qty_canceled,
  qty_refunded,
  qty_shipped,
  no_discount,
  discount_percent,
  amount_refunded,
  item_discount_amount,
  original_price,
  retail_price,
  retail_price_incl_tax,
  tax_amount,
  tax_percent,
  total_amount_incl_tax,
  total_amount
)
SELECT
created_at,
MAX(updated_at) AS updated_at,
increment_id,
entity_id,
order_currency_code,
state, 
status,
item_id,
product_id,
parent_item_id,
items_sku,
items_name,
is_free_shipping,
qty_ordered,
qty_canceled,
qty_refunded,
qty_shipped,
no_discount,
discount_percent,
amount_refunded,
item_discount_amount,
original_price,
retail_price,
retail_price_incl_tax,
tax_amount,
tax_percent,
total_amount_incl_tax,
total_amount
FROM `marine-cycle-484213-b4.magento.stg_magento_order`
WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
GROUP BY
created_at,
increment_id,
entity_id,
order_currency_code,
state, 
status,
item_id,
product_id,
parent_item_id,
items_sku,
items_name,
is_free_shipping,
qty_ordered,
qty_canceled,
qty_refunded,
qty_shipped,
no_discount,
discount_percent,
amount_refunded,
item_discount_amount,
original_price,
retail_price,
retail_price_incl_tax,
tax_amount,
tax_percent,
total_amount_incl_tax,
total_amount;
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'magento'
  ,'core_magento_order_item'
  ,'sp_magento_core_order_item_insert'
  ,'magento'
  ,'marine-cycle-484213-b4.magento.stg_magento_order'
  ,'marine-cycle-484213-b4.magento.core_magento_order_item'
  ,'marine-cycle-484213-b4.magento.sp_magento_core_order_item_insert'
  ,'marine-cycle-484213-b4.magento.raw_magento_order'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'magento'
  ,'core_magento_order_item'
  ,'sp_magento_core_order_item_insert'
  ,'magento'
  ,'marine-cycle-484213-b4.magento.stg_magento_order'
  ,'marine-cycle-484213-b4.magento.core_magento_order_item'
  ,'marine-cycle-484213-b4.magento.sp_magento_core_order_item_insert'
  ,'marine-cycle-484213-b4.magento.raw_magento_order'
);
  END IF;
END;