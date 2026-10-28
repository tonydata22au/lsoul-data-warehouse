CREATE TABLE `marine-cycle-484213-b4.reportdb.dash_materiality_config`
(
  pct_threshold FLOAT64,
  pace_threshold_pp FLOAT64,
  p_enable_abs_rule BOOL,
  abs_rule_top_n INT64,
  abs_rule_min_vnd FLOAT64,
  min_hist_weeks INT64,
  r2_min_abs_vnd FLOAT64,
  p_enable_zscore_rule BOOL,
  zscore_threshold FLOAT64,
  p_enable_marketing_rule BOOL,
  spend_pct_threshold FLOAT64,
  spend_min_vnd FLOAT64,
  roas_pct_threshold FLOAT64,
  traffic_pct_threshold FLOAT64
)
OPTIONS(
  description="Thresholds governing which movements reach the board narrative. Extended with a volatility rule (R5) and marketing rules (R6/R7)."
);
