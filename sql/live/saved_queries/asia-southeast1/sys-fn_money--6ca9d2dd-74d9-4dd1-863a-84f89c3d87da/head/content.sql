/* =============================================================================
   Money formatting for the dashboard pipeline -- NEW 2026-09-07
   -----------------------------------------------------------------------------
   Every VND figure that reaches a reader goes through these. Before this, each
   call site hard-coded its own divisor, so the report printed figures far
   outside their unit: 142656 mVND, 38525 mVND, 22030 kVND, 7522 kVND. Measured
   on the live pipeline, 71 of 202 money strings were mis-scaled.

   SCALE RULE - the unit follows the magnitude, one decimal:
       >= 1e9  ->  bVND      142,656,000,000  ->  142.7 bVND
       >= 1e6  ->  mVND            5,540,000  ->  5.5 mVND
       >= 1e3  ->  kVND              950,000  ->  950.0 kVND
       else    ->  VND                    999 ->  999 VND

   ---------------------------------------------------------------------------
   WHY THERE IS NO THOUSANDS SEPARATOR, AND WHY THE DECIMAL IS A DOT
   ---------------------------------------------------------------------------
   sp_dash_review_ai's det_numeric_ok extracts every figure from the narrative
   with the regex [0-9]+(?:\.[0-9]+)? and requires each one to appear in
   facts_block + action_block. That regex reads a dot as part of a number and a
   COMMA AS A BOUNDARY.

   So "5,5 mVND" is not read as 5.5 - it is read as two numbers, 5 and 5. A bare
   "5" would then sit in the facts block and authorise any stray 5 the model
   wrote anywhere in the narrative. Same for "1,234.5": that becomes 1 and 234.5.

   Vietnamese comma decimals therefore cannot be produced here without silently
   weakening the one gate that stops a fabricated figure reaching the board.
   HARD RULE 2 of the prompt says the same thing from the other side: numbers
   identical across languages, separators not localised.

   If the rendered report should show Vietnamese separators, do it in the
   notebook's presentation layer on SQL-computed columns - never on narrative
   text, which is what the gate reads.

   ---------------------------------------------------------------------------
   USE THE PAIR FUNCTION FOR RANGES
   ---------------------------------------------------------------------------
   fn_fmt_money_pair picks ONE unit for both ends, from the larger magnitude, so
   a range never straddles two units. "950.0 kVND->1.3 mVND" is unreadable;
   "1.0->1.3 mVND" is not. The cost is that the small end rounds - 950,000 shows
   as 1.0 - which is the right trade for a board sentence and is why the exact
   values stay in the numeric columns beside the text.
   ========================================================================== */

CREATE OR REPLACE FUNCTION `marine-cycle-484213-b4.reportdb.fn_money_scale`(v FLOAT64)
RETURNS FLOAT64
OPTIONS(description="Divisor for the unit fn_money_unit picks: 1e9 / 1e6 / 1e3 / 1.")
AS (
  CASE
    WHEN v IS NULL          THEN NULL
    WHEN ABS(v) >= 1e9      THEN 1e9
    WHEN ABS(v) >= 1e6      THEN 1e6
    WHEN ABS(v) >= 1e3      THEN 1e3
    ELSE 1
  END
);

CREATE OR REPLACE FUNCTION `marine-cycle-484213-b4.reportdb.fn_money_unit`(v FLOAT64)
RETURNS STRING
OPTIONS(description="Unit label matching fn_money_scale: bVND / mVND / kVND / VND.")
AS (
  CASE
    WHEN v IS NULL     THEN 'VND'
    WHEN ABS(v) >= 1e9 THEN 'bVND'
    WHEN ABS(v) >= 1e6 THEN 'mVND'
    WHEN ABS(v) >= 1e3 THEN 'kVND'
    ELSE 'VND'
  END
);

-- One VND figure, auto-scaled, unit included. NULL renders as 'n/a' rather than
-- '0 VND', so a missing figure is never mistaken for a real zero.
CREATE OR REPLACE FUNCTION `marine-cycle-484213-b4.reportdb.fn_fmt_money`(v FLOAT64)
RETURNS STRING
OPTIONS(description="VND auto-scaled to k/m/b with its unit, e.g. 5540000 -> '5.5 mVND'. Dot decimal, no thousands separator: det_numeric_ok reads a comma as a number boundary.")
AS (
  CASE
    WHEN v IS NULL     THEN 'n/a'
    WHEN ABS(v) >= 1e3 THEN CONCAT(FORMAT('%.1f', v / `marine-cycle-484213-b4.reportdb.fn_money_scale`(v)),
                                   ' ', `marine-cycle-484213-b4.reportdb.fn_money_unit`(v))
    ELSE CONCAT(FORMAT('%.0f', v), ' VND')
  END
);

-- A range in ONE unit, chosen from the larger end: 'a->b mVND'.
CREATE OR REPLACE FUNCTION `marine-cycle-484213-b4.reportdb.fn_fmt_money_pair`(a FLOAT64, b FLOAT64)
RETURNS STRING
OPTIONS(description="Two VND figures sharing one auto-scaled unit, e.g. '22.1->24.1 mVND'. Unit comes from the larger magnitude so a range never straddles two units.")
AS ((
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
));