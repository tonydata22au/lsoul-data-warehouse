--truncate table `marine-cycle-484213-b4.core_pancake.core_warehouse`
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.core_pancake.core_warehouse`
CLUSTER BY warehouse_id, warehouse_name
AS
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
        WHEN TRIM(warehouse_name)IN ('Kho Marketing')
        THEN 'M'    --Marketing
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
WHERE  1=1
AND DATE(proc_date) = "2026-06-02"
;