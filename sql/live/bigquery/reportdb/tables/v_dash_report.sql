CREATE TABLE `marine-cycle-484213-b4.reportdb.v_dash_report`
(
  page STRING,
  period_label STRING,
  headline_actual FLOAT64,
  headline_reference FLOAT64,
  headline_pct FLOAT64,
  excluded_target FLOAT64,
  pct_including_excluded FLOAT64,
  bills INT64,
  basket FLOAT64,
  data_as_of_note STRING,
  headline_note STRING,
  exec_summary_en STRING,
  exec_summary_vi STRING,
  narrative_en STRING,
  narrative_vi STRING,
  rule_narrative_en STRING,
  rule_narrative_vi STRING,
  action_block_en STRING,
  narrative_source STRING,
  ai_generated_at TIMESTAMP,
  model_endpoint STRING
);
