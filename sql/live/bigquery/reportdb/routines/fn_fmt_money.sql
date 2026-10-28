CREATE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_fmt_money(v FLOAT64) RETURNS STRING
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
