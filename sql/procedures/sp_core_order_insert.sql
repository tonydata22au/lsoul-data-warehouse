CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.core_pancake.sp_core_order_insert`()
BEGIN
/*
Author: Toan Pham
Date: 09/02/2026
Comment: This store procedure is to insert the data from stg_order -> core_order
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_core_order_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_order`);

  DECLARE data_insert_to_date DATE DEFAULT
                                              (SELECT MAX(DATE(inserted_at)) 
                                              FROM `marine-cycle-484213-b4.stg_pancake.stg_order`);
  DECLARE data_insert_from_date DATE DEFAULT
                                            (SELECT MIN(DATE(inserted_at))
                                              FROM `marine-cycle-484213-b4.stg_pancake.stg_order`
                                              WHERE DATE(proc_date) = data_proc_date);                                   

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.core_pancake.core_order` WHERE order_id IN (SELECT DISTINCT order_id
                                                                                FROM `marine-cycle-484213-b4.stg_pancake.stg_order`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.core_pancake.core_order`
  (
  inserted_at,
  updated_at,
  order_id,       
  system_id,
  status,
  status_name,
  assigning_seller_name,
  assigning_seller_email,
  time_assigned_seller,
  is_received_at_shop,
  is_customer_paid_fee,
  is_exchange_order,
  order_currency,
  order_sources_code,
  order_sources_name,
  items_count,
  total_quantity,
  total_price,
  shipping_fee,
  surcharge_amount,
  total_discount,
  prepaid_amount,
  transfer_amount,
  paid_cash,
  charged_by_card,
  charged_by_momo,
  charged_by_qrpay,
  bank_payments,
  tax_amount,
  partner_fee,
  buyer_total_amount,
  advanced_platform_fee_marketplace_voucher,
  total_marketplace_fee,
  total_price_after_sub_discount,
  exchange_payment_paid,
  cod,
  cod_money_to_collect,
  return_reason_code,
  return_reason,
  exchange_value,
  shipping_address_commune_name,
  shipping_address_province_name,
  warehouse_id,
  warehouse_name,
  marketplace_id,
  notes, 
  print_notes, 
  tags,
  customer_currency, 
  customer_id, 
  customer_succeed_order_count, 
  customer_inserted_at, 
  is_block_customer, 
  customer_updated_at, 
  customer_order_count, 
  customer_returned_order_count, 
  customer_purchased_amount, 
  customer_last_order_at, 
  customer_gender,
  advanced_platform_fee_affiliate_commission,
  advanced_platform_fee_diff_shipping_fee,
  advanced_platform_fee_payment_fee,
  advanced_platform_fee_seller_transaction_fee,
  advanced_platform_fee_service_fee,
  assigning_care_name,
  assigning_care_email,
  time_assigned_care,
  last_editor_name,
  last_editor_email,
  creator_name,
  creator_email
  )
  SELECT
  inserted_at,
  MAX(updated_at) AS updated_at,
  order_id,       
  system_id,
  status,
  status_name,
  assigning_seller_name,
  assigning_seller_email,
  time_assigned_seller,
  is_received_at_shop,
  is_customer_paid_fee,
  is_exchange_order,
  order_currency,
  order_sources AS order_sources_code,
  order_sources_name,
  items_count,
  total_quantity,
  total_price,
  shipping_fee,
  surcharge_amount,
  total_discount,
  prepaid_amount,
  transfer_amount,
  paid_cash,
  charged_by_card,
  charged_by_momo,
  charged_by_qrpay,
  bank_payments,
  tax_amount,
  partner_fee,
  buyer_total_amount,
  advanced_platform_fee_marketplace_voucher,
  marketplace_fee AS total_marketplace_fee,
  total_price_after_sub_discount,
  exchange_payment_info AS exchange_payment_paid,
  cod,
  cod_money_to_collect,
  return_reason_code,
  return_reason,
  exchange_value,
  shipping_address_commune_name,
  shipping_address_province_name,
  warehouse_id,
  warehouse_name,
  marketplace_id,
  notes, 
  print_notes, 
  tags,
  customer_currency, 
  customer_customer_id AS customer_id, 
  customer_succeed_order_count, 
  customer_inserted_at, 
  is_block_customer, 
  customer_updated_at, 
  customer_order_count, 
  customer_returned_order_count, 
  customer_purchased_amount, 
  customer_last_order_at, 
  customer_gender,
  advanced_platform_fee_affiliate_commission,
  advanced_platform_fee_diff_shipping_fee,
  advanced_platform_fee_payment_fee,
  advanced_platform_fee_seller_transaction_fee,
  advanced_platform_fee_service_fee,
  assigning_care_name,
  assigning_care_email,
  time_assigned_care,
  last_editor_name,
  last_editor_email,
  creator_name,
  creator_email
  FROM `marine-cycle-484213-b4.stg_pancake.stg_order`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
  GROUP BY
  inserted_at,
  order_id,       
  system_id,
  status,
  status_name,
  assigning_seller_name,
  assigning_seller_email,
  time_assigned_seller,
  is_received_at_shop,
  is_customer_paid_fee,
  is_exchange_order,
  order_currency,
  order_sources_code,
  order_sources_name,
  items_count,
  total_quantity,
  total_price,
  shipping_fee,
  surcharge_amount,
  total_discount,
  prepaid_amount,
  transfer_amount,
  paid_cash,
  charged_by_card,
  charged_by_momo,
  charged_by_qrpay,
  bank_payments,
  tax_amount,
  partner_fee,
  buyer_total_amount,
  advanced_platform_fee_marketplace_voucher,
  total_marketplace_fee,
  total_price_after_sub_discount,
  exchange_payment_paid,
  cod,
  cod_money_to_collect,
  return_reason_code,
  return_reason,
  exchange_value,
  shipping_address_commune_name,
  shipping_address_province_name,
  warehouse_id,
  warehouse_name,
  marketplace_id,
  notes, 
  print_notes, 
  tags,
  customer_currency, 
  customer_id, 
  customer_succeed_order_count, 
  customer_inserted_at, 
  is_block_customer, 
  customer_updated_at, 
  customer_order_count, 
  customer_returned_order_count, 
  customer_purchased_amount, 
  customer_last_order_at, 
  customer_gender,
  advanced_platform_fee_affiliate_commission,
  advanced_platform_fee_diff_shipping_fee,
  advanced_platform_fee_payment_fee,
  advanced_platform_fee_seller_transaction_fee,
  advanced_platform_fee_service_fee,
  assigning_care_name,
  assigning_care_email,
  time_assigned_care,
  last_editor_name,
  last_editor_email,
  creator_name,
  creator_email;
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'inserted_at'
  ,1
  ,'core_pancake'
  ,'core_order'
  ,'sp_core_order_insert'
  ,'core_pancake'  
  ,'marine-cycle-484213-b4.stg_pancake.stg_order'
  ,'marine-cycle-484213-b4.core_pancake.core_order'
  ,'marine-cycle-484213-b4.core_pancake.sp_core_order_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_order'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'inserted_at'
  ,1
  ,'core_pancake'
  ,'core_order'
  ,'sp_core_order_insert'
  ,'core_pancake'  
  ,'marine-cycle-484213-b4.stg_pancake.stg_order'
  ,'marine-cycle-484213-b4.core_pancake.core_order'
  ,'marine-cycle-484213-b4.core_pancake.sp_core_order_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_order'
);

  END IF;
END;