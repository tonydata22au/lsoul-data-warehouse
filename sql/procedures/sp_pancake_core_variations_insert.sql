CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4`.core_pancake.sp_pancake_core_variations_insert()
BEGIN
/*
Author: Toan Pham
Date: 19/05/2026
Comment: This store procedure is to insert the data from stg_variations -> core_variations  &  core_variation_warehouse
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_pancake_core_variations_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_variations`);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.core_pancake.core_variations` WHERE variation_id IN (SELECT DISTINCT variation_id
                                                                                FROM `marine-cycle-484213-b4.stg_pancake.stg_variations`
                                                                                WHERE DATE(proc_date) = data_proc_date);
                                                                        
    
  INSERT INTO `marine-cycle-484213-b4.core_pancake.core_variations`
  (
  inserted_at,
  updated_at,
  product_id,
  product_code,
  variation_id, 
  variation_display_id, 
  size_name,
  size_value,
  color_name,
  color_value,
  retail_price,
  retail_price_after_discount,
  last_imported_price,
  total_purchase_price,
  price_at_counter,
  wholesale_price,
  remain_quantity,
  is_hidden, 
  is_locked,
  is_removed,
  is_sell_negative,
  is_composite,
  variation_attributes
)
  SELECT
  inserted_at,
  MAX(updated_at) AS updated_at,
  product_id,
  REGEXP_EXTRACT(variation_display_id, r'^([^-]+)') AS product_code, 
  variation_id, 
  variation_display_id,
  size_name,
  size_value,
  color_name,
  color_value,
  retail_price,
  retail_price_after_discount,
  last_imported_price,
  total_purchase_price,
  price_at_counter,
  wholesale_price,
  remain_quantity,
  is_hidden, 
  is_locked,
  is_removed,
  is_sell_negative,
  is_composite,
  CASE 
      WHEN size_value NOT LIKE '' AND  color_value NOT LIKE '' THEN CONCAT(size_value,' - ',color_value) 
      WHEN size_value LIKE '' AND  color_value NOT LIKE '' THEN color_value
      WHEN size_value NOT LIKE '' AND  color_value  LIKE '' THEN size_value
      ELSE NULL
  END variation_attributes
  FROM `marine-cycle-484213-b4.stg_pancake.stg_variations`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
  GROUP BY
  inserted_at,
  product_id,
  variation_id, 
  variation_display_id, 
  size_name,
  size_value,
  color_name,
  color_value,
  retail_price,
  retail_price_after_discount,
  last_imported_price,
  total_purchase_price,
  price_at_counter,
  wholesale_price,
  remain_quantity,
  is_hidden, 
  is_locked,
  is_removed,
  is_sell_negative,
  is_composite,
  variation_attributes;
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'core_pancake'
  ,'core_variations'
  ,'sp_pancake_core_variations_insert'
  ,'core_pancake'
  ,'marine-cycle-484213-b4.stg_pancake.stg_variations'
  ,'marine-cycle-484213-b4.core_pancake.core_variations'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_variations_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_product_variations'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'core_pancake'
  ,'core_variations'
  ,'sp_pancake_core_variations_insert'
  ,'core_pancake'
  ,'marine-cycle-484213-b4.stg_pancake.stg_variations'
  ,'marine-cycle-484213-b4.core_pancake.core_variations'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_variations_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_product_variations'
  );  

  END IF;
END;
