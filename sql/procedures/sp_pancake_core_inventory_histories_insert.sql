CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4`.core_pancake.sp_pancake_core_inventory_histories_insert()
BEGIN
/*
Author: Toan Pham
Date: 19/05/2026
Comment: This store procedure is to insert the data from stg_product -> core_product
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_pancake_core_inventory_histories_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_inventory_histories`);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.core_pancake.core_inventory_histories` WHERE inventory_history_id IN (SELECT DISTINCT inventory_history_id
                                                                                FROM `marine-cycle-484213-b4.stg_pancake.stg_inventory_histories`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.core_pancake.core_inventory_histories`
  (
    inserted_at,
    inventory_history_id,
    record_id,
    table_name,
    note_type,
    type,
    ref_display_id,
    warehouse_id,
    warehouse_name,
    quantity,
    remain_quantity,
    variation_inserted_at,
    variation_updated_at,
    product_id,
    product_code,
    product_launch_date,
    variation_id,
    variation_display_id,
    variation_name,
    remain_qty,
    total_qty,
    is_composite,
    is_hidden,
    is_locked,
    is_removed,
    is_sell_negative_variation,
    avg_price,
    last_imported_price,
    price_counter,
    retail_price,
    retail_price_after_discount,
    wholesale_price,
    inv_warehouse_id,
    inv_warehouse_name,
    inv_actual_remain_qty,
    inv_remain_qty,
    inv_total_qty
)
  SELECT
    inserted_at,
    inventory_history_id,
    record_id,
    table_name,
    note_type,
    type,
    ref_display_id,
    warehouse_id,
    warehouse_name,
    quantity,
    remain_quantity,
    variation_inserted_at,
    variation_updated_at,
    variation_product_id AS product_id,
    REGEXP_EXTRACT(variation_display_id, r'^([^-]+)') AS product_code,
    DATE(
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(variation_display_id, r'\d{6}'), 1, 2) AS INT64) + 2000,
    SAFE_CAST(SUBSTR(REGEXP_EXTRACT(variation_display_id, r'\d{6}'), 3, 2) AS INT64),
    01
    ) product_launch_date,
    variation_id,
    variation_display_id,
    variation_name,
    variation_remain_quantity AS remain_qty,
    variation_total_quantity AS total_qty,
    variation_is_composite AS is_composite,
    variation_is_hidden AS is_hidden,
    variation_is_locked AS is_locked,
    variation_is_removed AS is_removed,
    variation_is_sell_negative_variation AS is_sell_negative_variation,
    avg_price,
    variation_last_imported_price AS last_imported_price,
    variation_price_at_counter AS price_counter,
    variation_retail_price AS retail_price,
    variation_retail_price_after_discount AS retail_price_after_discount,
    variation_wholesale_price AS wholesale_price,
    current_inventory_warehouse_id AS inv_warehouse_id,
    current_inventory_name AS inv_warehouse_name,
    current_inventory_actual_remain_quantity AS inv_actual_remain_qty,
    current_inventory_remain_quantity AS inv_remain_qty,
    current_inventory_total_quantity AS inv_total_qty
  FROM `marine-cycle-484213-b4.stg_pancake.stg_inventory_histories`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"));
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'inserted_at'
  ,1
  ,'core_pancake'
  ,'core_inventory_histories'
  ,'sp_pancake_core_inventory_histories_insert'
  ,'core_pancake'
  ,'marine-cycle-484213-b4.stg_pancake.stg_inventory_histories'
  ,'marine-cycle-484213-b4.core_pancake.core_inventory_histories'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_inventory_histories_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_inventory_histories'
);

  ELSE 

   CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'inserted_at'
  ,1
  ,'core_pancake'
  ,'core_inventory_histories'
  ,'sp_pancake_core_inventory_histories_insert'
  ,'core_pancake'
  ,'marine-cycle-484213-b4.stg_pancake.stg_inventory_histories'
  ,'marine-cycle-484213-b4.core_pancake.core_inventory_histories'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_inventory_histories_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_inventory_histories'
  );  

  END IF;
END;
