CREATE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_money_unit(v FLOAT64) RETURNS STRING
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
