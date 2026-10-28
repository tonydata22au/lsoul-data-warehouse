CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4`.dianplus.sp_dianplus_core_inventory_insert()
BEGIN
/*
Author: Toan Pham
Date: 19/05/2026
Comment: This store procedure is to insert the data from stg_dianplus_inventory -> core_dianplus_inventory
Run syntax: 
  CALL `marine-cycle-484213-b4.dianplus.sp_dianplus_core_inventory_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.dianplus.stg_dianplus_inventory`);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.dianplus.core_dianplus_inventory` WHERE skuId IN (SELECT DISTINCT skuId
                                                                                FROM `marine-cycle-484213-b4.dianplus.stg_dianplus_inventory`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.dianplus.core_dianplus_inventory`
  (
  updated_at, 
  brandId,
  warehouse_name,
  spuId, 
  spuCode, 
  skuId,
  product_code, 
  product_launch_date, 
  skuCode, 
  realNum, 
  lockNum, 
  canUseNum, 
  frozenNum, 
  transitNum, 
  defectNum
)
  SELECT
  DATE(inserted_at) AS updated_at, 
  brandId,
  warehouse_name,
  spuId, 
  spuCode, 
  skuId,
  REGEXP_EXTRACT(skuCode, r'^([^-]+)') AS product_code,
    DATE(
      SAFE_CAST(SUBSTR(REGEXP_EXTRACT(skuCode, r'\d{6}'), 1, 2) AS INT64) + 2000,
      SAFE_CAST(SUBSTR(REGEXP_EXTRACT(skuCode, r'\d{6}'), 3, 2) AS INT64),
      01
      ) product_launch_date, 
  skuCode, 
  realNum, 
  lockNum, 
  canUseNum, 
  frozenNum, 
  transitNum, 
  defectNum
  FROM `marine-cycle-484213-b4.dianplus.stg_dianplus_inventory` i
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"));
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'updated_at'
  ,1
  ,'dianplus'
  ,'core_dianplus_inventory'
  ,'sp_dianplus_core_inventory_insert'
  ,'dianplus'
  ,'marine-cycle-484213-b4.dianplus.stg_dianplus_inventory'
  ,'marine-cycle-484213-b4.dianplus.core_dianplus_inventory'
  ,NULL
  ,'marine-cycle-484213-b4.dianplus.raw_dianplus_inventory'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'updated_at'
  ,1
  ,'dianplus'
  ,'core_dianplus_inventory'
  ,'sp_dianplus_core_inventory_insert'
  ,'pipelines'
  ,'marine-cycle-484213-b4.dianplus.stg_dianplus_inventory'
  ,'marine-cycle-484213-b4.dianplus.core_dianplus_inventory'
  ,NULL
  ,'marine-cycle-484213-b4.dianplus.raw_dianplus_inventory'
);

  END IF;
END;
