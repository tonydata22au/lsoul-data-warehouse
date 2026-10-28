CREATE TABLE `marine-cycle-484213-b4.reportdb.dash_ai_guidance`
(
  guidance_id STRING,
  guidance_version INT64,
  page STRING,
  guidance_text STRING,
  origin_feedback_id STRING,
  is_active BOOL,
  activated_at TIMESTAMP,
  retired_at TIMESTAMP,
  retire_reason STRING
)
OPTIONS(
  description="Active prompt guidance. Subordinate to the hard rules by construction: injected before them in the prompt."
);
