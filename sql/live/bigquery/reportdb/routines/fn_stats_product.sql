CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_stats_product(i_type INT64, i_number_year_back INT64, i_days_range INT64, i_avg_units_sold_expect INT64, i_FromDate DATE, i_ToDate DATE)
AS
WITH cte_01 AS (
  SELECT 
  *
  ,IFNULL(ROUND(SAFE_DIVIDE(units_sold_day_range,(units_sold_day_range + sl_ton_kho)),2),0)  AS sell_through_rate
  ,IFNULL(ROUND(SAFE_DIVIDE(
              units_sold_day_range
              ,i_days_range
              ),2),0) AS sale_velocity
  FROM `marine-cycle-484213-b4.reportdb.fn_product_inventory_summary`(i_type,i_number_year_back,i_days_range,i_FromDate,i_ToDate)
)

,cte_02 AS (
 SELECT 
 *
 ,IFNULL(ROUND(SAFE_DIVIDE(sl_ton_kho, sale_velocity),0),0) AS DOH
,DATE_SUB(DATE_TRUNC(CURRENT_DATE(), DAY), INTERVAL sort_desc DAY) AS d_date
 FROM cte_01 i
)

--4 Define clear thresholds for BLACK, RED, YELLOW, GREEN - "no sales", “slow” vs “normal” vs “fast”
,cte_03 AS (
SELECT
*
,CASE 
   WHEN is_sale_end = 1 OR emty_stock_days > 14  THEN 0
   WHEN sell_through_rate = 0 THEN 1
   WHEN sell_through_rate < 0.25 THEN 2
   WHEN sell_through_rate < 0.5 THEN 3
   ELSE 4
   END AS sell_through_band
,CASE 
   WHEN is_sale_end = 1 OR emty_stock_days > 14  THEN 0
   WHEN sale_velocity < (i_avg_units_sold_expect/days_range/2/2) THEN 1
   WHEN sale_velocity < (i_avg_units_sold_expect/days_range/2) THEN 2
   WHEN sale_velocity < i_avg_units_sold_expect/days_range THEN 3
   ELSE 4
   END AS velocity_band

/*Days of Inventory On Hand: 1 (worst) → 4 (best).
    Special case: DOH=0 with sales = sold out = best (4).
    Special case: DOH=0 with no sales = dead = worst (1).
*/
,CASE 
   WHEN is_sale_end = 1  OR emty_stock_days > 14  THEN 0
   WHEN DOH < 0 THEN 0
   WHEN DOH = 0 AND sale_velocity > i_avg_units_sold_expect/days_range  THEN 4
   WHEN DOH = 0 AND sale_velocity < (i_avg_units_sold_expect/days_range/2/2) THEN 1
   WHEN DOH <= 90  THEN 4 --HIGH
   WHEN DOH <= 180 THEN 3
   WHEN DOH < 360 THEN 2
   ELSE 1 --severe overstock / dead stock
   END AS DOH_band
FROM cte_02
)
,cte_04 AS (
SELECT
*
,CASE 
    WHEN (sell_through_band = 0 AND velocity_band = 0) OR is_sale_end = 1 OR emty_stock_days > 14 THEN 'NO STOCK OR SALE ENDED'
    WHEN sell_through_band + velocity_band + DOH_band >= 11 THEN '1-GREEN'
    WHEN sell_through_band + velocity_band + DOH_band >= 7 OR product_days_since_launch <= 56 THEN '2-YELLOW'
    WHEN sell_through_band + velocity_band + DOH_band >= 4 THEN '3-RED'
    ELSE '4-BLACK'
    END AS colour_bucket
  FROM cte_03
)
--ACTION COMMENTS:
/* "Green":  "Fast mover — prioritise replenishment to avoid stockout. Maintain promotional visibility and ensure supply chain is ready.",
    "Yellow": "Normal mover — monitor velocity trends. Ensure stock covers the next 1–2 sales periods. No urgent action needed.",
    "Red":    "Slow mover with excess stock — initiate clearance promotions, markdowns, or bundle deals urgently to reduce DOH.",
    "Black":  "No sales in period — review for discontinuation, deep markdown, write-off, or return to supplier.",
*/

SELECT 
*
,CASE 
    WHEN colour_bucket = '1-GREEN' THEN CONCAT('Sku bán chạy và sl hàng đủ để bán trong ',DOH,' ngày tới')
    WHEN colour_bucket = '2-YELLOW' THEN CONCAT('Sku có doanh số bán bình thường và sl hàng đủ trong ',DOH,' ngày tới')
    WHEN colour_bucket = '3-RED' THEN CONCAT('Sku bán chậm, cần đẩy doanh số để xả tồn kho, số ngày tồn cao (',DOH,') ngày cần ưu tiên cho cleareance')
    WHEN colour_bucket = '4-BLACK' THEN 'Sku chưa bán hoặc đã ngưng sản xuất'
    ELSE 'N/A'
    END AS comments

FROM cte_04;
