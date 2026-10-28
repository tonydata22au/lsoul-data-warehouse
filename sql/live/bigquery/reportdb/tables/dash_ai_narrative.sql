CREATE TABLE `marine-cycle-484213-b4.reportdb.dash_ai_narrative`
(
  page STRING NOT NULL,
  period_key STRING NOT NULL,
  period_label STRING,
  facts_hash STRING,
  exec_summary_en STRING,
  exec_summary_vi STRING,
  narrative_en STRING,
  narrative_vi STRING,
  model_endpoint STRING,
  prompt_tokens INT64,
  output_tokens INT64,
  gen_status STRING,
  generated_at TIMESTAMP
)
OPTIONS(
  description="Cached bilingual narrative with executive summary. Written only by sp_dash_generate_ai."
);
