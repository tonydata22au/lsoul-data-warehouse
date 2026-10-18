select
sum(revenue_cn)
FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china`(0)

union all

select
sum(revenue_cn)
FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(0,0)
and DATE(DATE_TRUNC(order_date, MONTH)) = '2026-05-01'



SELECT
a.month,
a.rev,
b.rev,
IF(a.rev = b.rev,1,0)
FROM
(
  select
  DATE(DATE_TRUNC(order_date,MONTH)) month,
  sum(revenue_cn) rev
  FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china`(0)
  GROUP BY 1
) a
JOIN
(
  select
  DATE(DATE_TRUNC(order_date, MONTH)) month,
  sum(revenue_cn) rev
  FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(0,0)
  
  GROUP BY 1
) b
ON a.month = b.month
order by 1 desc



select
CONCAT('_',order_id) AS order_id,
* EXCEPT (order_id,variation_code)
FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_v2`(0,0)
WHERE DATE(DATE_TRUNC(order_date, MONTH)) = '2026-05-01'
AND level_3 = 'Shopee'
AND revenue_thai > 0
--AND order_id = '582493553146955553'
ORDER BY 1 DESC


select
CONCAT('_',order_id) AS order_id,
* EXCEPT (order_id)
FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_vn`(0)
WHERE DATE(DATE_TRUNC(order_date, MONTH)) = '2026-04-01'
AND revenue <> 0
--AND order_id = '70609'
ORDER BY 1 DESC


-- V1. Atomic grain holds. EXPECT excess_rows = 0.
SELECT COUNT(*) AS rows_out,
       COUNT(DISTINCT FORMAT('%t|%t|%t|%t|%t', order_date,level_1, level_2, level_3, order_id)) AS keys,
       COUNT(*) - COUNT(DISTINCT FORMAT('%t|%t|%t|%t|%t', order_date,level_1, level_2, level_3, order_id)) AS excess_rows
FROM `marine-cycle-484213-b4.reportdb.fn_sale_ecom_china_v2`(0,0)

-- V2. Taobao/Tmall no longer inflated. EXPECT ratio ~= 1.00 vs raw source.
WITH mine AS (
  SELECT ROUND(SUM(gmv)/1e6) AS gmv_mVND
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`
  WHERE level_3 IN ('Tmall','Taobao') AND period_date BETWEEN '2026-08-03' AND '2026-08-09'
),
raw AS (
  SELECT ROUND(SUM(items_buyer_paid_amount)*3800/1e6) AS gmv_mVND
  FROM `marine-cycle-484213-b4.jushuitan.core_jushuitan_taobao_tmall_order_manual`
  WHERE shop_id IN (20209463,20209689) AND items_buyer_paid_amount > 0
    AND DATE(vn_order_date) BETWEEN '2026-08-03' AND '2026-08-09'
)
SELECT mine.gmv_mVND AS mine, raw.gmv_mVND AS raw_source,
       ROUND(SAFE_DIVIDE(mine.gmv_mVND, raw.gmv_mVND),2) AS ratio
FROM mine CROSS JOIN raw;

-- V2b. NaN / NULL guard. EXPECT all zeros.
SELECT COUNTIF(IS_NAN(nmv)) AS nan_nmv, COUNTIF(IS_NAN(gmv)) AS nan_gmv,
       COUNTIF(nmv IS NULL) AS null_nmv, COUNTIF(units_sold IS NULL) AS null_units
FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day`;
