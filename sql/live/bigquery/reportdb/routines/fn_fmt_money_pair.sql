CREATE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_fmt_money_pair(a FLOAT64, b FLOAT64) RETURNS STRING
OPTIONS(
  description="Two VND figures sharing one auto-scaled unit, e.g. '22.1->24.1 mVND'. Unit comes from the larger magnitude so a range never straddles two units.")
AS (
(
  SELECT CONCAT(
           FORMAT(IF(s = 1, '%.0f', '%.1f'), IFNULL(a, 0) / s), '->',
           FORMAT(IF(s = 1, '%.0f', '%.1f'), IFNULL(b, 0) / s), ' ',
           CASE s WHEN 1e9 THEN 'bVND' WHEN 1e6 THEN 'mVND' WHEN 1e3 THEN 'kVND' ELSE 'VND' END)
  FROM (
    SELECT CASE
             WHEN GREATEST(ABS(IFNULL(a,0)), ABS(IFNULL(b,0))) >= 1e9 THEN 1e9
             WHEN GREATEST(ABS(IFNULL(a,0)), ABS(IFNULL(b,0))) >= 1e6 THEN 1e6
             WHEN GREATEST(ABS(IFNULL(a,0)), ABS(IFNULL(b,0))) >= 1e3 THEN 1e3
             ELSE 1
           END AS s
  )
)
);
