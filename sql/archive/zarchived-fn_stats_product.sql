CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_stats_product`(
  i_type INT64 -- 0: daily, 1: lastest stock value by SKU only (exclude warehouses)
  ,i_number_year_back INT64 --0: current year
  ,i_days_range INT64 --30,90 
  ,i_avg_units_sold_expect INT64 --SL ban trung binh mong muon
  ,i_FromDate DATE --'2026-01-01'
  ,i_ToDate DATE
)
  
AS 
/*
Author: Toan Pham
Date: 29/05/2026
Comment: 
Sell‑through rate (%) = Units sold in period / Units received or opening stock for that period ×100.
SKU velocity (units/day) per SKU per channel: SKU velocity = Units sold in period ÷ Number of days in period.
Days of Inventory on Hand (DOH) per SKU per channel: DOH = Current stock level ÷ Average daily sales (velocity). DOH tells you how many days your current stock will last at current selling speed.

A simple, practical framework per channel:
- Time window: last 30 days for in‑season monitoring, plus last 90 days for seasonal view.
- For each SKU per channel calculate:
    > 30‑day sell‑through %
    > 30‑day velocity (units/day)
    > DOH (days)

Fast movers: Green
- Sell‑through ≥ 50–60% over 30–60 days (for fashion tops, dresses, etc.).
- OR Velocity ≥ 1 unit/day (for main channels).
- DOH ≤ 30–45 days.

Normal movers: Yellow
- Sell‑through 20–50% in 30–60 days.
- Velocity around 0.3–1 unit/day.
- DOH 30–90 days.

Slow movers: Red
- Sell‑through < 20–30% over 60 days, or < 10–15% over 30 days.
- Velocity < 0.2 units/day.
- DOH > 90 days (very slow); DOH > 180 days (critical slow stock).

Building report:
1. Export sales by SKU and channel for last 30 and 90 days.
2. Export current stock by SKU and channel.
3. In your sheet:
  - Compute velocity and DOH per SKU per channel.
  - Mark SKUs where DOH > 90 days OR 30‑day sell‑through < 20%.
4. Sort by:
  - Largest DOH first, then
  - Highest stock value (if you have cost/price per SKU).


Testing:
  SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_stats_product`(0,0,90,9,'2026-01-01','2026-06-21')  where period_date >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 0 MONTH) order by 1 desc --90-day sales
  SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_stats_product`(1,0,90,9,'2026-01-01','2026-06-21')   --90-day sales 
  SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_stats_product`(0,0,90,9,null,null)   --90-day sales 
*/
(
--variation_master_table
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

FROM cte_04

)

