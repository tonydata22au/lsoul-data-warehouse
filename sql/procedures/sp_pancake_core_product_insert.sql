CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.core_pancake.sp_pancake_core_product_insert`()
BEGIN
/*
Author: Toan Pham
Date: 19/05/2026
Comment: This store procedure is to insert the data from stg_product -> core_product
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_pancake_core_product_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_product`);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.core_pancake.core_product` WHERE raw_product_id IN (SELECT DISTINCT product_id
                                                                                FROM `marine-cycle-484213-b4.stg_pancake.stg_product`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.core_pancake.core_product`
  (
  inserted_at,
  updated_at,
  raw_product_id,
  display_id,
  product_code, 
  product_name,
  product_launch_date, 
  product_attributes, 
  supplier_product_ids, 
  product_tags
)
  SELECT
  inserted_at,
  MAX(updated_at) AS updated_at,
  product_id AS raw_product_id,
  display_id,
  REGEXP_EXTRACT(display_id, r'^([^-]+)') AS product_code,
  product_name,
  DATE(
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(display_id, r'\d{6}'), 1, 2) AS INT64) + 2000,
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(display_id, r'\d{6}'), 3, 2) AS INT64),
    01
    ) product_launch_date,
  product_attributes,
  supplier_product_ids,
  product_tags
  FROM `marine-cycle-484213-b4.stg_pancake.stg_product`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
  GROUP BY
  inserted_at,
  product_id,
  display_id,
  product_name, 
  product_attributes, 
  supplier_product_ids, 
  product_tags;
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'core_pancake'
  ,'core_product'
  ,'sp_pancake_core_product_insert'
  ,'core_pancake'
  ,'marine-cycle-484213-b4.stg_pancake.stg_product'
  ,'marine-cycle-484213-b4.core_pancake.core_product'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_product_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_product_variations'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'core_pancake'
  ,'core_product'
  ,'sp_pancake_core_product_insert'
  ,'core_pancake'
  ,'marine-cycle-484213-b4.stg_pancake.stg_product'
  ,'marine-cycle-484213-b4.core_pancake.core_product'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_product_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_product_variations'
  );  

  END IF;
END;