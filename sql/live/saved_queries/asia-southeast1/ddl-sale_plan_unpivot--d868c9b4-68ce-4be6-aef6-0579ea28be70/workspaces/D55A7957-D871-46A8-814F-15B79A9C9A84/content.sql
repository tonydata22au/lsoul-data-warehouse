CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.stg_sale_plan_2026`
AS
SELECT
  `KÊNH` AS channel,
  CASE
    WHEN length(metric_name)= 2 THEN SAFE_CAST(CONCAT(2026,'-',metric_name,'-',01) AS DATETIME) ELSE SAFE_CAST(CONCAT(metric_name,'-',12,'-',31) AS DATETIME) END AS sale_month_date,
  CASE
    WHEN length(metric_name)= 2 THEN  EXTRACT(MONTH FROM (SAFE_CAST(CONCAT(2026,'-',metric_name,'-',01) AS DATETIME))) ELSE EXTRACT(MONTH FROM (SAFE_CAST(CONCAT(metric_name,'-',12,'-',31) AS DATETIME))) END AS month,
  CASE
    WHEN length(metric_name)= 2 THEN  1 ELSE 0 END AS is_sale_by_month,
  metric_name,
  metric_value,
  CASE
    WHEN UPPER(TRIM(`KÊNH`)) IN ('LSOUL') THEN 0
    WHEN UPPER(TRIM(`KÊNH`)) IN ('VIỆT NAM','THÁI LAN','TRUNG QUỐC') THEN 1
    ELSE 2
  END AS channel_level,
  
  CASE
    WHEN UPPER(TRIM(`KÊNH`)) LIKE '%ECOMMERCE%' THEN 'Sale Ecommerce'
    WHEN UPPER(TRIM(`KÊNH`)) LIKE '%OFFLINE STORE%' THEN 'Store'
    WHEN UPPER(TRIM(`KÊNH`)) LIKE '%ONLINE%' THEN 'Sale Online'
    WHEN UPPER(TRIM(`KÊNH`)) LIKE '%WHOLESALES%' THEN 'Wholesales'
    WHEN UPPER(TRIM(`KÊNH`)) LIKE '%Pop-up%' THEN 'Pop-up'
    ELSE NULL
  END AS sale_channel_type,

  CASE
    WHEN UPPER(TRIM(`KÊNH`)) LIKE '%VN%' OR  UPPER(TRIM(`KÊNH`)) LIKE 'VIỆT NAM' THEN 'VIETNAM'
    WHEN UPPER(TRIM(`KÊNH`)) LIKE '%TL%' OR  UPPER(TRIM(`KÊNH`)) LIKE 'THÁI LAN' THEN 'THAILAND'
    WHEN UPPER(TRIM(`KÊNH`)) LIKE '%TQ%'  OR  UPPER(TRIM(`KÊNH`)) LIKE 'TRUNG QUỐC' THEN 'CHINA'
    WHEN UPPER(TRIM(`KÊNH`)) LIKE '%LSOUL%' THEN 'TOTAL'
    ELSE NULL
  END AS sale_country

FROM `marine-cycle-484213-b4.reportdb.raw_sale_plan_2026`
UNPIVOT (
  metric_value
  FOR metric_name IN (
    Y2025 AS '2025',
    Y2026 AS '2026',
    M1 AS '01',
    M2 AS '02',
    M3 AS '03',
    M4 AS '04',
    M5 AS '05',
    M6 AS '06',
    M7 AS '07',
    M8 AS '08',
    M9 AS '09',
    M10 AS '10',
    M11 AS '11',
    M12 AS '12'
  )
)
ORDER BY channel, metric_name;