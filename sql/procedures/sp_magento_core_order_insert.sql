CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.magento.sp_magento_core_order_insert`()
BEGIN
/*
Author: Toan Pham
Date: 05/07/2026
Comment: This store procedure is to insert the data from stg_order -> core_order
Run syntax: 
  CALL `marine-cycle-484213-b4.magento.sp_magento_core_order_insert`() --today date
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

  DELETE `marine-cycle-484213-b4.magento.core_magento_order` WHERE entity_id IN (SELECT DISTINCT entity_id
                                                                                FROM `marine-cycle-484213-b4.magento.stg_magento_order`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.magento.core_magento_order`
  (
  created_at,
  updated_at,
increment_id,
entity_id,
order_currency_code,
state,
status,
customer_email,
customer_firstname,
customer_lastname,
customer_group_id,
customer_is_guest,
customer_note_notify,
email_sent,
is_virtual,
remote_ip,
store_id,
store_currency_code,
store_name,
shipping_description,
shipping_amount,
shipping_tax_amount,
discount_amount,
subtotal,
total_paid,
total_due,
grand_total,
total_item_count,
total_qty_ordered,
billing_address_billing,
billing_address_entity_id,
billing_address_parent_id,
billing_address_email,
billing_address_firstname,
billing_address_lastname,
billing_address_telephone,
billing_address_street,
billing_address_city,
billing_address_postcode,
billing_address_region_code,
billing_address_region,
billing_address_country_id,
payment_parent_id,
payment_account_status,
payment_method,
payment_shipping_amount,
payment_shipping_captured,
payment_amount_authorized,
payment_amount_ordered,
payment_amount_paid,
mp_extra_fee
)
SELECT
created_at,
MAX(updated_at) AS updated_at,
increment_id,
entity_id,
order_currency_code,
state,
status,
customer_email,
customer_firstname,
customer_lastname,
customer_group_id,
customer_is_guest,
customer_note_notify,
email_sent,
is_virtual,
remote_ip,
store_id,
store_currency_code,
SPLIT(store_name, '\n')[OFFSET(0)] AS store_name,
shipping_description,
shipping_amount,
shipping_tax_amount,
discount_amount,
subtotal,
total_paid,
total_due,
grand_total,
total_item_count,
total_qty_ordered,
billing_address_billing,
billing_address_entity_id,
billing_address_parent_id,
billing_address_email,
billing_address_firstname,
billing_address_lastname,
billing_address_telephone,
billing_address_street,
billing_address_city,
billing_address_postcode,
billing_address_region_code,
billing_address_region,
billing_address_country_id,
payment_parent_id,
payment_account_status,
payment_method,
payment_shipping_amount,
payment_shipping_captured,
payment_amount_authorized,
payment_amount_ordered,
payment_amount_paid,
mp_extra_fee
FROM `marine-cycle-484213-b4.magento.stg_magento_order`
WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
GROUP BY
created_at,
increment_id,
entity_id,
order_currency_code,
state,
status,
customer_email,
customer_firstname,
customer_lastname,
customer_group_id,
customer_is_guest,
customer_note_notify,
email_sent,
is_virtual,
remote_ip,
store_id,
store_currency_code,
store_name,
shipping_description,
shipping_amount,
shipping_tax_amount,
discount_amount,
subtotal,
total_paid,
total_due,
grand_total,
total_item_count,
total_qty_ordered,
billing_address_billing,
billing_address_entity_id,
billing_address_parent_id,
billing_address_email,
billing_address_firstname,
billing_address_lastname,
billing_address_telephone,
billing_address_street,
billing_address_city,
billing_address_postcode,
billing_address_region_code,
billing_address_region,
billing_address_country_id,
payment_parent_id,
payment_account_status,
payment_method,
payment_shipping_amount,
payment_shipping_captured,
payment_amount_authorized,
payment_amount_ordered,
payment_amount_paid,
mp_extra_fee;
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'magento'
  ,'core_magento_order'
  ,'sp_magento_core_order_insert'
  ,'magento'
  ,'marine-cycle-484213-b4.magento.stg_magento_order'
  ,'marine-cycle-484213-b4.magento.core_magento_order'
  ,'marine-cycle-484213-b4.magento.sp_magento_core_order_insert'
  ,'marine-cycle-484213-b4.magento.raw_magento_order'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'magento'
  ,'core_magento_order'
  ,'sp_magento_core_order_insert'
  ,'magento'
  ,'marine-cycle-484213-b4.magento.stg_magento_order'
  ,'marine-cycle-484213-b4.magento.core_magento_order'
  ,'marine-cycle-484213-b4.magento.sp_magento_core_order_insert'
  ,'marine-cycle-484213-b4.magento.raw_magento_order'
);
  END IF;
END;