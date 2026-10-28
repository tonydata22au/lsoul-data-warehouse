CREATE PROCEDURE `marine-cycle-484213-b4`.jushuitan.sp_jushuitan_core_inventory_insert()
BEGIN
/*
Author: Toan Pham
Date: 19/05/2026
Comment: This store procedure is to insert the data from stg_jushuitan_inventory -> core_ushuitan_inventory
Run syntax: 
  CALL `marine-cycle-484213-b4.jushuitan.sp_jushuitan_core_inventory_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_inventory`);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.jushuitan.core_jushuitan_inventory` WHERE sku_id IN (SELECT DISTINCT sku_id
                                                                                FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_inventory`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.jushuitan.core_jushuitan_inventory`
  (
  proc_date,
  modified,
  vn_modified,
  ts,
  product_code,
  product_launch_date,
  item_id,
  sku_id,
  name, 
  qty, 
  in_qty, 
  return_qty, 
  defective_qty,
  purchase_qty, 
  allocate_qty, 
  virtual_qty
  )
  SELECT
  proc_date,
  modified,
  vn_modified,
  ts, 
  REGEXP_EXTRACT(sku_id, r'^([^-]+)') AS product_code,
      DATE(
        SAFE_CAST(SUBSTR(REGEXP_EXTRACT(sku_id, r'\d{6}'), 1, 2) AS INT64) + 2000,
        SAFE_CAST(SUBSTR(REGEXP_EXTRACT(sku_id, r'\d{6}'), 3, 2) AS INT64),
        01
        ) product_launch_date, 
  item_id,
  sku_id, 
  name, 
  qty, 
  in_qty, 
  return_qty, 
  defective_qty,
  purchase_qty, 
  allocate_qty, 
  virtual_qty
  FROM `marine-cycle-484213-b4.jushuitan.stg_jushuitan_inventory` 
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"))
  AND item_id is not null AND UPPER(item_id) NOT LIKE '%TEST%';
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'vn_modified'
  ,'vn_modified'
  ,1
  ,'jushuitan'
  ,'core_jushuitan_inventory'
  ,'sp_jushuitan_core_inventory_insert'
  ,'jushuitan'
  ,'marine-cycle-484213-b4.jushuitan.stg_jushuitan_inventory'
  ,'marine-cycle-484213-b4.jushuitan.core_jushuitan_inventory'
  ,'marine-cycle-484213-b4.jushuitan.sp_jushuitan_core_inventory_insert'
  ,'marine-cycle-484213-b4.jushuitan.raw_jushuitan_inventory'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'vn_modified'
  ,'vn_modified'
  ,1
  ,'jushuitan'
  ,'core_jushuitan_inventory'
  ,'sp_jushuitan_core_inventory_insert'
  ,'jushuitan'
  ,'marine-cycle-484213-b4.jushuitan.stg_jushuitan_inventory'
  ,'marine-cycle-484213-b4.jushuitan.core_jushuitan_inventory'
  ,'marine-cycle-484213-b4.jushuitan.sp_jushuitan_core_inventory_insert'
  ,'marine-cycle-484213-b4.jushuitan.raw_jushuitan_inventory'
);

  END IF;
END;
