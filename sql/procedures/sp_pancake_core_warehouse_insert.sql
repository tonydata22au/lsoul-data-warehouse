CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.core_pancake.sp_pancake_core_warehouse_insert`()
BEGIN
/*
Author: Toan Pham
Date: 19/05/2026
Comment: This store procedure is to insert the data from stg_inventory_histories` -> core_warehouse
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_pancake_core_warehouse_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_inventory_histories`);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.core_pancake.core_warehouse` WHERE warehouse_id IN (SELECT DISTINCT warehouse_id
                                                                                FROM `marine-cycle-484213-b4.stg_pancake.stg_inventory_histories`
                                                                                WHERE DATE(proc_date) = data_proc_date);
    
  INSERT INTO `marine-cycle-484213-b4.core_pancake.core_warehouse`
  (
  warehouse_id,
  warehouse_code,  
  warehouse_name,
  country, 
  warehouse_type, 
  is_active,
  inserted_at, 
  updated_at
  )
  SELECT DISTINCT
    warehouse_id,
    sysdb.udf_remove_vn_accents(warehouse_name) AS warehouse_code,
    warehouse_name,
    CASE 
        WHEN TRIM(UPPER(warehouse_name)) LIKE '%THÁI%' 
            OR TRIM(UPPER(warehouse_name)) LIKE '%THAI%'
            OR TRIM(warehouse_name) IN  ('Kho Emsphere','Kho Central World','Central Ladprao','Kho Offfice Thailand','Kho Thái (Back-up)')
        THEN 'THAILAND'
        WHEN TRIM(UPPER(warehouse_name)) LIKE '%TRUNG QUỐC%' 
            OR TRIM(UPPER(warehouse_name)) LIKE '%CHINA%' 
            OR TRIM(warehouse_name) IN ('Kho Trung Quốc (Back-up)')
        THEN 'CHINA'
        -- WHEN TRIM(UPPER(warehouse_name)) LIKE '%VIỆT NAM%' 
        --     OR TRIM(UPPER(warehouse_name)) LIKE '%VIET NAM%'
        --     OR TRIM(UPPER(warehouse_name)) LIKE '%VIETNAM%' 
        --     OR TRIM(warehouse_name) IN ('Kho Nguyễn Trãi (Back-up)','Kho Whole Sale','Kho Online', 'Kho Ecommerce Việt Nam','Kho Nguyễn Trãi','Kho Tổng 480F','LJIN','Kho Marketing') 
        -- THEN 'VIETNAM'
        ELSE 'VIETNAM'
    END AS country,
    CASE 
        WHEN TRIM(UPPER(warehouse_name)) LIKE '%BACK-UP%' 
            OR TRIM(UPPER(warehouse_name)) LIKE '%BACKUP%'
            OR TRIM(warehouse_name) IN ('Kho Tổng 480F', 'LJIN')
        THEN 'B'    --Backup
        WHEN TRIM(warehouse_name) IN ('Kho Marketing','Kho Offfice Thailand') THEN 'M'    --Marketing
        WHEN TRIM(warehouse_name) IN ('LSOUL HEAD OFFICE','Kho hàng lỗi') THEN 'NONE' --Kho khong dung de ban,va tinh ton
        ELSE 'P'    --Primary
    END AS warehouse_type,
    CASE 
        WHEN MAX(DATE(inserted_at)) OVER (PARTITION BY warehouse_id ORDER BY inserted_at DESC) < DATE_SUB(DATE_TRUNC(CURRENT_DATE(), DAY), INTERVAL 30 DAY)
        THEN 0
        ELSE 1
    END AS is_active,
    DATETIME(DATE_SUB(DATE_TRUNC(CURRENT_DATE(), DAY), INTERVAL 1 DAY)) AS inserted_at,
    CURRENT_DATETIME('Asia/Ho_Chi_Minh') AS updated_at
  FROM `marine-cycle-484213-b4.stg_pancake.stg_inventory_histories`
  WHERE DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"));
  
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'inserted_at'
  ,1
  ,'core_pancake'
  ,'core_warehouse'
  ,'sp_pancake_core_warehouse_insert'
  ,'core_pancake'
  ,'marine-cycle-484213-b4.stg_pancake.stg_inventory_histories'
  ,'marine-cycle-484213-b4.core_pancake.core_warehouse'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_warehouse_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_inventory_histories'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'inserted_at'
  ,1
  ,'core_pancake'
  ,'core_warehouse'
  ,'sp_pancake_core_warehouse_insert'
  ,'core_pancake'
  ,'marine-cycle-484213-b4.stg_pancake.stg_inventory_histories'
  ,'marine-cycle-484213-b4.core_pancake.core_warehouse'
  ,'marine-cycle-484213-b4.core_pancake.sp_pancake_core_warehouse_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_inventory_histories'
  );  

  END IF;


  -- 1. Create the temp table inside the procedure body
  CREATE OR REPLACE TEMP TABLE temp_active_warehouses AS
  SELECT
    MAX(DATE(i.inserted_at)) AS last_inserted_at
    ,core.warehouse_id
    ,core.warehouse_name
   FROM  `marine-cycle-484213-b4.core_pancake.core_warehouse` core 
   JOIN `marine-cycle-484213-b4.core_pancake.core_inventory_histories` i ON i.warehouse_id = core.warehouse_id
   WHERE core.is_active = 1
   GROUP BY 2,3
   HAVING  IFNULL(DATE_DIFF(CURRENT_DATE(),MAX(DATE(i.inserted_at)), DAY),0) > 30 ;

  UPDATE `marine-cycle-484213-b4.core_pancake.core_warehouse`
  SET is_active = 0
      ,updated_at = CURRENT_DATETIME('Asia/Ho_Chi_Minh')
  WHERE warehouse_id IN (SELECT warehouse_id FROM temp_active_warehouses);

END;