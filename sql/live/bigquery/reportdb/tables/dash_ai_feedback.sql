CREATE TABLE `marine-cycle-484213-b4.reportdb.dash_ai_feedback`
(
  feedback_id STRING,
  submitted_by STRING,
  submitted_at TIMESTAMP,
  page STRING,
  period_key STRING,
  rating INT64,
  feedback_text STRING,
  proposed_guidance STRING,
  source STRING,
  status STRING,
  screen_flag STRING,
  reviewed_by STRING,
  reviewed_at TIMESTAMP
)
OPTIONS(
  description="Feedback on AI narratives. feedback_text is untrusted input and is NEVER placed in a prompt. Only an APPROVED proposed_guidance line reaches the model."
);
