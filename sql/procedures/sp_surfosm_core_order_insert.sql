CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.surfosm.sp_surfosm_core_order_insert`()
BEGIN
/*
Author: Toan Pham
Date: 02/05/2026
Comment: This store procedure is to insert the data from stg_surfosm_order -> core_surfosm_order
Run syntax: 
  CALL `marine-cycle-484213-b4.surfosm.sp_surfosm_core_order_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`);

  DECLARE data_insert_to_date DATE DEFAULT
                                              (SELECT MAX(parameter_date) 
                                              FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`
                                              WHERE DATE(proc_date) = data_proc_date);
  DECLARE data_insert_from_date DATE DEFAULT
                                              (SELECT MIN(parameter_date)
                                              FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`
                                              WHERE DATE(proc_date) = data_proc_date);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.surfosm.core_surfosm_order` WHERE parameter_date >= data_insert_from_date;
    
  INSERT INTO `marine-cycle-484213-b4.surfosm.core_surfosm_order`
  (
  parameter_date,
  inserted_at,
  order_number,
  external_order_id,
  channel,
  shipping,
  status,
  status_code,
  customer_name,
  customer_address,
  customer_district,
  customer_province,
  customer_postal_code,
  customer_phone_no,
  customer_email,
  payment_paid_at,
  payment_shipping_fee_original,
  payment_shipping_fee_discount_platform,
  payment_shipping_fee_discount_seller,
  payment_shipping_fee,
  payment_discount_platform_voucher,
  payment_discount_platform_payment_promotion,
  payment_discount_platform_order,
  payment_discount_platform_total,
  payment_coupon_seller,
  payment_discount_seller,
  payment_discount_seller_total,
  payment_subtotal,
  payment_discount,
  payment_total
  )
  SELECT DISTINCT
  parameter_date,
  inserted_at,
  order_number,
  external_order_id,
  channel,
  shipping,
  status,
  status_code,
  customer_name,
  customer_address,
  customer_district,
  customer_province,
  customer_postal_code,
  customer_phone_no,
  customer_email,
  payment_paid_at,
  payment_shipping_fee_original,
  payment_shipping_fee_discount_platform,
  payment_shipping_fee_discount_seller,
  payment_shipping_fee,
  payment_discount_platform_voucher,
  payment_discount_platform_payment_promotion,
  payment_discount_platform_order,
  payment_discount_platform_total,
  payment_coupon_seller,
  payment_discount_seller,
  payment_discount_seller_total,
  payment_subtotal,
  payment_discount,
  payment_total
  FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"));
  
  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'surfosm'
            ,'core_surfosm_order'
            ,1
            ,1
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_surfosm_core_order_insert'
            ,'surfosm'
            ,'marine-cycle-484213-b4.surfosm.core_surfosm_order'
            ,'marine-cycle-484213-b4.surfosm.sp_surfosm_core_order_insert'
          );

  ELSE 

  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'surfosm'
            ,'core_surfosm_order'
            ,0
            ,0
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_surfosm_core_order_insert'
            ,'surfosm'
            ,'marine-cycle-484213-b4.surfosm.core_surfosm_order'
            ,'marine-cycle-484213-b4.surfosm.sp_surfosm_core_order_insert'
          );
  END IF;
END;