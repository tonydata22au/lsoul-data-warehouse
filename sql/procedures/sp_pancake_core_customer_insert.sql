CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.core_pancake.sp_pancake_core_customer_insert`()
BEGIN
/*
Author: Toan Pham
Date: 19/05/2026
Comment: This store procedure is to insert the data from stg_customer -> core_customer
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_pancake_core_customer_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_customer`);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.core_pancake.core_customer` WHERE customer_id IN (SELECT DISTINCT customer_id
                                                                                FROM `marine-cycle-484213-b4.stg_pancake.stg_customer`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.core_pancake.core_customer`
  (
  inserted_at,
  updated_at,
  customer_id,
  username,
  tags,
  fb_id,
  is_block,
  assigned_user_id,
  creator_name,
  creator_id,
  currency,
  order_count,
  succeed_order_count,
  returned_order_count,
  purchased_amount,
  last_order_at,
  order_sources,
  shop_customer_addresses_id,
  shop_customer_addresses_country_code,
  shop_customer_addresses_province_id,
  shop_customer_addresses_commune_id
)
  SELECT
  inserted_at,
  MAX(updated_at) AS updated_at,
  customer_id,
  username,
  tags,
  fb_id,
  is_block,
  assigned_user_id,
  creator_name,
  creator_id,
  currency,
  order_count,
  succeed_order_count,
  returned_order_count,
  purchased_amount,
  last_order_at,
  order_sources,
  shop_customer_addresses_id,
  shop_customer_addresses_country_code,
  shop_customer_addresses_province_id,
  shop_customer_addresses_commune_id
  FROM `marine-cycle-484213-b4.stg_pancake.stg_customer`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
  GROUP BY
  inserted_at,
  customer_id,
  username,
  tags,
  fb_id,
  is_block,
  assigned_user_id,
  creator_name,
  creator_id,
  currency,
  order_count,
  succeed_order_count,
  returned_order_count,
  purchased_amount,
  last_order_at,
  order_sources,
  shop_customer_addresses_id,
  shop_customer_addresses_country_code,
  shop_customer_addresses_province_id,
  shop_customer_addresses_commune_id;
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'core_pancake'
  ,'core_customer'
  ,'sp_pancake_core_customer_insert'
  ,'core_pancake'  
  ,'marine-cycle-484213-b4.stg_pancake.stg_customer'
  ,'marine-cycle-484213-b4.core_pancake.core_customer'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_customer_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_customer'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'core_pancake'
  ,'core_customer'
  ,'sp_pancake_core_customer_insert'
  ,'core_pancake'  
  ,'marine-cycle-484213-b4.stg_pancake.stg_customer'
  ,'marine-cycle-484213-b4.core_pancake.core_customer'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_customer_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_customer'
  );  

  END IF;
END;