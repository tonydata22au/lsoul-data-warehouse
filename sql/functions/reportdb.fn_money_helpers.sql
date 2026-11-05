CREATE OR REPLACE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_money_scale(v FLOAT64) RETURNS FLOAT64
OPTIONS(
  description="Divisor for the unit fn_money_unit picks: 1e9 / 1e6 / 1e3 / 1.")
AS (
CASE
    WHEN v IS NULL          THEN NULL
    WHEN ABS(v) >= 1e9      THEN 1e9
    WHEN ABS(v) >= 1e6      THEN 1e6
    WHEN ABS(v) >= 1e3      THEN 1e3
    ELSE 1
  END
);

CREATE OR REPLACE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_money_unit(v FLOAT64) RETURNS STRING
OPTIONS(
  description="Unit label matching fn_money_scale: bVND / mVND / kVND / VND.")
AS (
CASE
    WHEN v IS NULL     THEN 'VND'
    WHEN ABS(v) >= 1e9 THEN 'bVND'
    WHEN ABS(v) >= 1e6 THEN 'mVND'
    WHEN ABS(v) >= 1e3 THEN 'kVND'
    ELSE 'VND'
  END
);

CREATE OR REPLACE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_fmt_money(v FLOAT64) RETURNS STRING
OPTIONS(
  description="VND auto-scaled to k/m/b with its unit, e.g. 5540000 -> '5.5 mVND'. Dot decimal, no thousands separator: det_numeric_ok reads a comma as a number boundary.")
AS (
CASE
    WHEN v IS NULL     THEN 'n/a'
    WHEN ABS(v) >= 1e3 THEN CONCAT(FORMAT('%.1f', v / `marine-cycle-484213-b4.reportdb.fn_money_scale`(v)),
                                   ' ', `marine-cycle-484213-b4.reportdb.fn_money_unit`(v))
    ELSE CONCAT(FORMAT('%.0f', v), ' VND')
  END
);

CREATE OR REPLACE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_fmt_money_pair(a FLOAT64, b FLOAT64) RETURNS STRING
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
