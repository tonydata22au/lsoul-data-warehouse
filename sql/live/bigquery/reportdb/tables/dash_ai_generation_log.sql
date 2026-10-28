CREATE TABLE `marine-cycle-484213-b4.reportdb.dash_ai_generation_log`
(
  logged_at TIMESTAMP,
  page STRING,
  period_key STRING,
  facts_hash STRING,
  finish_reason STRING,
  api_status STRING,
  prompt_tokens INT64,
  answer_tokens INT64,
  thinking_tokens INT64,
  gen_status STRING,
  len_exec_summary_en INT64,
  len_narrative_en INT64,
  len_narrative_vi INT64
)
OPTIONS(
  description="N5: one row per AI.GENERATE attempt. dash_ai_narrative is MERGEd in place, so a failed attempt used to leave no trace once a retry overwrote it."
);
