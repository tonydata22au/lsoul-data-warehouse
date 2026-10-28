CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.sale_plan_2026_daily`
AS
WITH monthly AS (
  SELECT
    `KENH` AS channel,
    CASE
      WHEN LENGTH(metric_name) = 2 THEN SAFE_CAST(CONCAT('2026-', metric_name, '-01') AS DATETIME)
      ELSE SAFE_CAST(CONCAT(metric_name, '-12-31') AS DATETIME)
    END AS sale_month_date,
    CASE
      WHEN LENGTH(metric_name) = 2 THEN EXTRACT(MONTH FROM SAFE_CAST(CONCAT('2026-', metric_name, '-01') AS DATETIME))
      ELSE EXTRACT(MONTH FROM SAFE_CAST(CONCAT(metric_name, '-12-31') AS DATETIME))
    END AS month,
    CASE
      WHEN LENGTH(metric_name) = 2 THEN 1 ELSE 0
    END AS is_sale_by_month,
    metric_name,
    metric_value,
    CASE
      WHEN UPPER(TRIM(`KENH`)) IN ('LSOUL') THEN 0
      WHEN UPPER(TRIM(`KENH`)) IN ('VIỆT NAM', 'THÁI LAN', 'TRUNG QUỐC') OR  UPPER(TRIM(`KENH`)) IN ('VIET NAM', 'THAI LAN', 'TRUNG QUOC') THEN 1
      ELSE 2
    END AS channel_level,
    CASE
      WHEN UPPER(TRIM(`KENH`)) LIKE '%ECOMMERCE%'    THEN 'Sale Ecommerce'
      WHEN UPPER(TRIM(`KENH`)) LIKE '%OFFLINE STORE%' THEN 'Store'
      WHEN UPPER(TRIM(`KENH`)) LIKE '%ONLINE%'        THEN 'Sale Online'
      WHEN UPPER(TRIM(`KENH`)) LIKE '%WHOLESALES%'    THEN 'Wholesales'
      WHEN UPPER(TRIM(`KENH`)) LIKE '%Pop-up%'        THEN 'Pop-up'
      ELSE NULL
    END AS sale_channel_type,
    CASE
      WHEN UPPER(TRIM(`KENH`)) LIKE '%VN%'    OR UPPER(TRIM(`KENH`)) = 'VIỆT NAM'  OR UPPER(TRIM(`KENH`)) = 'VIET NAM'   THEN 'VIETNAM'
      WHEN UPPER(TRIM(`KENH`)) LIKE '%TL%'    OR UPPER(TRIM(`KENH`)) = 'THÁI LAN'  OR UPPER(TRIM(`KENH`)) = 'THAI LAN'  THEN 'THAILAND'
      WHEN UPPER(TRIM(`KENH`)) LIKE '%TQ%'    OR UPPER(TRIM(`KENH`)) = 'TRUNG QUỐC' OR UPPER(TRIM(`KENH`)) = 'TRUNG QUOC' THEN 'CHINA'
      WHEN UPPER(TRIM(`KENH`)) LIKE '%LSOUL%'                                         THEN 'TOTAL'
      ELSE NULL
    END AS sale_country
  FROM 
  (SELECT * EXCEPT (Y2025,Y2026),
    SAFE_CAST(Y2025 AS INT64) Y2025,
    SAFE_CAST(Y2026 AS INT64) Y2026,
  FROM `marine-cycle-484213-b4.reportdb.raw_sale_plan_2026`
  )
  UNPIVOT (
    metric_value FOR metric_name IN (
      Y2025 AS '2025',
      Y2026 AS '2026',
      M1  AS '01', M2  AS '02', M3  AS '03',
      M4  AS '04', M5  AS '05', M6  AS '06',
      M7  AS '07', M8  AS '08', M9  AS '09',
      M10 AS '10', M11 AS '11', M12 AS '12'
    )
  )
),

-- Generate day numbers 1 to 31
day_series AS (
  SELECT day_of_month
  FROM UNNEST(GENERATE_ARRAY(1, 31)) AS day_of_month
),

-- Compute days in each month using LAST_DAY
monthly_with_days AS (
  SELECT
    m.*,
    EXTRACT(DAY FROM LAST_DAY(m.sale_month_date, MONTH)) AS days_in_month
  FROM monthly m
)
,day_breakdown AS (
SELECT
  m.channel,
  m.sale_month_date,
  m.month,
  is_sale_by_month,
  m.metric_name,
  m.metric_value,

  -- day_of_month: populated for monthly rows only
  CASE WHEN m.is_sale_by_month = 1 THEN d.day_of_month ELSE NULL END AS day_of_month,

  -- Full date for each day of the month
  CASE
    WHEN m.is_sale_by_month = 1
    THEN DATETIME_ADD(
           DATE_TRUNC(CAST(m.sale_month_date AS DATE), MONTH),
           INTERVAL (d.day_of_month - 1) DAY
         )
    ELSE NULL
  END AS sale_date,

  -- Daily value = monthly total / number of days in that month
  CASE
    WHEN m.is_sale_by_month = 1 THEN SAFE_DIVIDE(m.metric_value, m.days_in_month)
    ELSE NULL
  END AS metric_value_daily,

  m.channel_level,
  m.sale_channel_type,
  m.sale_country

FROM monthly_with_days m

-- For monthly rows: cross join to all valid days of that month
-- For year rows (is_sale_by_month = 0): keep as single row (JOIN to day 1 only as placeholder)
LEFT JOIN day_series d
  ON m.is_sale_by_month = 0            -- year rows: no expansion needed
  OR d.day_of_month <= m.days_in_month -- month rows: only valid days (handles Feb 28/29)

WHERE
  m.is_sale_by_month = 0               -- keep year summary rows as-is
  OR d.day_of_month IS NOT NULL        -- keep all expanded daily rows
)
SELECT
sale_country,
channel,
channel_level,
sale_channel_type,
sale_month_date,
sale_date,
month,
day_of_month,
metric_name,
metric_value,
metric_value_daily,
CASE WHEN EXTRACT(DAY FROM sale_date) = 1 THEN is_sale_by_month ELSE 0 END is_for_monthly_report,
CASE WHEN is_sale_by_month = 1 AND channel_level > 1 THEN 1 ELSE 0 END is_for_daily_report
FROM day_breakdown
ORDER BY channel, metric_name, day_of_month;
