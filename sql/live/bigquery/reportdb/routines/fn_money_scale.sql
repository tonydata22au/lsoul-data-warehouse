CREATE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_money_scale(v FLOAT64) RETURNS FLOAT64
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
