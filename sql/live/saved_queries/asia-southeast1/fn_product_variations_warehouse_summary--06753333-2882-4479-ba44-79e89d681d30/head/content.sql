CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_product_variations_warehouse_summary`(
  i_type INT64 -- 0: group by product, 1: group by variations, 2: current stock by variations only
  ,i_number_year_back INT64 --0: current year
  ,i_country STRING --'',VIETNAM, THAILAND, CHINA
)
AS
/*
Author: Toan Pham
Date: 29/05/2026
Comment: get inventory of each variation/product in each warehouses
call:
    SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_product_variations_warehouse_summary`(1,0,'')  order by 1 desc
*/
(
WITH stock_in_by_warehouse AS (
SELECT
inserted_at
,product_code
,variation_display_id
,variation_name
,product_launch_date
,inv_warehouse_id
,inv_warehouse_name
,stock_in_qty
,stock_total_current_qty_by_warehouse
,inv_actual_remain_qty 
,stock_total_current_qty_all_warehouses
,note_type
,inv_total_qty
,retail_price
,ref_display_id
,inventory_history_id
,record_id
,warehouse_id
,table_name

FROM
(
  SELECT DISTINCT
  i.inserted_at
  ,i.inv_warehouse_id
  ,i.inv_warehouse_name
  ,i.product_code 
  ,i.variation_display_id
  ,variation_name
  ,product_launch_date
  ,CASE WHEN warehouse_id = inv_warehouse_id THEN quantity ELSE 0 END AS stock_in_qty    --qty imported
  ,i.inv_remain_qty  AS stock_total_current_qty_by_warehouse --total stock current at the time of the qty imported
  ,i.inv_actual_remain_qty 
  ,remain_quantity  AS stock_total_current_qty_all_warehouses --Tong hang ton tai thoi diem them stock moi
  ,i.note_type
  ,i.inv_total_qty
  ,i.retail_price
  ,last_imported_price
  ,i.ref_display_id
  ,i.inventory_history_id
  ,i.warehouse_id
  ,i.table_name
  ,i.record_id
  FROM `marine-cycle-484213-b4.core_pancake.core_inventory_histories` i
  WHERE 1=1
  AND LEFT(i.variation_display_id,2) NOT IN ('TG','HT','HN','HH','TD')
  ORDER BY 1 DESC,4
  
) T
WHERE 1=1
AND DATE_TRUNC(inserted_at, YEAR) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), YEAR), INTERVAL i_number_year_back YEAR)
--AND variation_display_id = 'A26032889'
--AND ref_display_id = '30664'
ORDER BY 1,2 desc
)
,stats_variations_by_warehouse AS (
SELECT 
ROW_NUMBER () OVER (PARTITION BY import.variation_display_id, import.inv_warehouse_id, DATE(import.inserted_at) ORDER BY import.inserted_at DESC, inventory_history_id DESC) AS sort_num
,import.inserted_at
,product_code
,variation_display_id
,variation_name
,product_launch_date
,import.inv_warehouse_id
,import.inv_warehouse_name 
,import.stock_in_qty
,import.stock_total_current_qty_by_warehouse
--,inv_actual_remain_qty
,import.stock_total_current_qty_all_warehouses
,CASE 
  WHEN table_name = 'purchases' AND warehouse_id = '28fc9c4c-6ad6-4dd3-8dda-bc44397c9e0f' --Kho Tổng 480F
  THEN stock_in_qty  
  ELSE 0
  END AS new_stock_in_qty
,CASE 
  WHEN table_name = 'purchases' AND warehouse_id = '28fc9c4c-6ad6-4dd3-8dda-bc44397c9e0f' --Kho Tổng 480F
  THEN stock_total_current_qty_all_warehouses  
  ELSE 0
  END AS all_stock_qty
,import.retail_price 
,import.ref_display_id
,import.note_type
,inventory_history_id
,record_id
FROM stock_in_by_warehouse AS import
ORDER BY 3,2 desc,5
)

,stats_variations_by_warehouse_insertedat AS (
SELECT
DATE(i.inserted_at) AS inserted_at
,product_code
,variation_display_id
,variation_name
,product_launch_date
,inv_warehouse_id
,i.inv_warehouse_name
,retail_price
,SUM(stock_in_qty) AS stock_in_qty
,SUM(CASE WHEN sort_num = 1 THEN stock_total_current_qty_by_warehouse ELSE 0 END) AS stock_total_current_qty_by_warehouse
,SUM(new_stock_in_qty) AS new_stock_in_qty
,SUM(CASE WHEN sort_num = 1 THEN stock_total_current_qty_all_warehouses ELSE 0 END) AS stock_total_current_qty_all_warehouses
FROM stats_variations_by_warehouse i
GROUP BY 1,2,3,4,5,6,7,8
ORDER BY 1 desc,2,7 desc,3
)

,master_stats_variations AS (
SELECT
TIMESTAMP_TRUNC(i.inserted_at, DAY) AS inserted_at
,product_code
,variation_display_id AS variation_code
,variation_name
,product_launch_date
,inv_warehouse_id AS warehouse_id
,inv_warehouse_name AS warehouse_name
,w.warehouse_code
,w.country
,w.is_active
,w.warehouse_type
,CASE 
    WHEN  ROW_NUMBER() OVER (PARTITION BY variation_display_id, inv_warehouse_id ORDER BY DATE(i.inserted_at) DESC) = 1
    THEN 'tổng hiện tại'
    ELSE SAFE_CAST(DATE(i.inserted_at) AS STRING)  
    END AS d_date_filter 
,new_stock_in_qty AS sl_nhap_moi_tu_sx
,stock_in_qty AS sl_nhap_kho
,stock_total_current_qty_by_warehouse AS sl_ton_kho
,stock_total_current_qty_all_warehouses AS tong_sl_co_the_ban_trong_kho
,CASE 
    WHEN new_stock_in_qty > 0 THEN retail_price * new_stock_in_qty 
    WHEN stock_total_current_qty_by_warehouse > 0 THEN retail_price * stock_total_current_qty_by_warehouse 
    ELSE 0
  END AS tong_gia_tri_hang_ton_kho_theo_gia_ban 
FROM stats_variations_by_warehouse_insertedat i
JOIN `marine-cycle-484213-b4.core_pancake.core_warehouse` w ON i.inv_warehouse_id = w.warehouse_id
WHERE i_country = '' OR w.country = i_country
)

--GROUP BY PRODUCT
SELECT inserted_at,product_code, product_code AS variation_code, variation_name, product_launch_date,warehouse_id,warehouse_name
,warehouse_code
,country
,is_active
,warehouse_type
,d_date_filter
,SUM(sl_nhap_moi_tu_sx) AS sl_nhap_moi_tu_sx
,SUM(sl_nhap_kho) AS sl_nhap_kho
,MAX(sl_ton_kho) AS sl_ton_kho
,MAX(tong_sl_co_the_ban_trong_kho) AS tong_sl_co_the_ban_trong_kho
,SUM(tong_gia_tri_hang_ton_kho_theo_gia_ban) AS tong_gia_tri_hang_ton_kho_theo_gia_ban
FROM master_stats_variations WHERE i_type = 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12



UNION ALL

--GROUP BY VARIATIONS
SELECT * FROM master_stats_variations WHERE i_type = 1

UNION ALL

--GROUP BY VARIATIONS, latest stock stats only
SELECT * FROM master_stats_variations WHERE i_type = 2
 QUALIFY ROW_NUMBER() OVER (
  PARTITION BY product_code, variation_code, warehouse_id
  ORDER BY inserted_at desc
  ) = 1 
ORDER BY 1 DESC,3, 7
)


