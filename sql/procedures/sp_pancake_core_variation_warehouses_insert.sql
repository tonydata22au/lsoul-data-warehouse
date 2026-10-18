CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.core_pancake.sp_pancake_core_variation_warehouses_insert`()
BEGIN
/*
Author: Toan Pham
Date: 19/05/2026
Comment: This store procedure is to insert the data from stg_variation_warehouses ->  core_variation_warehouses
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_pancake_core_variation_warehouses_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_variation_warehouses`);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.core_pancake.core_variation_warehouses` WHERE variation_id IN (SELECT DISTINCT variation_id
                                                                                FROM `marine-cycle-484213-b4.stg_pancake.stg_variation_warehouses`
                                                                                WHERE DATE(proc_date) = data_proc_date);
                                                                 

  INSERT INTO `marine-cycle-484213-b4.core_pancake.core_variation_warehouses`
  (
  updated_at,
  inserted_at,
  product_id, 
  product_tags,
  variation_id,
  warehouse_id,
  actual_remain_qty, 
  pending_qty, 
  remain_qty, 
  returning_qty, 
  total_qty, 
  waiting_qty
)
  SELECT
  MAX(updated_at) AS updated_at,
  inserted_at,
  product_id, 
  product_tags,
  variation_id,
  warehouse_id,
  actual_remain_qty, 
  pending_qty, 
  remain_qty, 
  returning_qty, 
  total_qty, 
  waiting_qty
  FROM `marine-cycle-484213-b4.stg_pancake.stg_variation_warehouses`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
  GROUP BY
  inserted_at,
  product_id, 
  product_tags,
  variation_id,
  warehouse_id,
  actual_remain_qty, 
  pending_qty, 
  remain_qty, 
  returning_qty, 
  total_qty, 
  waiting_qty;
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'core_pancake'
  ,'core_variation_warehouses'
  ,'sp_pancake_core_variation_warehouses_insert'
  ,'core_pancake'  
  ,'marine-cycle-484213-b4.stg_pancake.stg_variation_warehouses'
  ,'marine-cycle-484213-b4.core_pancake.core_variation_warehouses'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_variation_warehouses_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_product_variations'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'updated_at'
  ,'updated_at'
  ,1
  ,'core_pancake'
  ,'core_variation_warehouses'
  ,'sp_pancake_core_variation_warehouses_insert'
  ,'core_pancake'  
  ,'marine-cycle-484213-b4.stg_pancake.stg_variation_warehouses'
  ,'marine-cycle-484213-b4.core_pancake.core_variation_warehouses'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_variation_warehouses_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_product_variations'
  );  

  END IF;
END;