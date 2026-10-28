CREATE TABLE `marine-cycle-484213-b4.reportdb.dash_ai_review`
(
  review_id STRING,
  page STRING,
  period_key STRING,
  facts_hash STRING,
  attempt_no INT64,
  guidance_version INT64,
  unsupported_numbers ARRAY<STRING>,
  det_numeric_ok BOOL,
  det_owner_tags_ok BOOL,
  det_action_count_ok BOOL,
  det_sku_ok BOOL,
  det_diacritics_ok BOOL,
  det_headings_ok BOOL,
  det_no_traffic_claim BOOL OPTIONS(description="No footfall claim about a physical store. Store footfall is not instrumented anywhere; website sessions are, and are governed by det_traffic_claim_ok."),
  det_exec_summary_ok BOOL,
  det_consistency_ok BOOL,
  missing_points ARRAY<STRING>,
  missing_from_summary ARRAY<STRING>,
  fabricated_points ARRAY<STRING>,
  det_pass BOOL,
  judge_numeric_fidelity INT64,
  judge_shape_adherence INT64,
  judge_diagnosis_fidelity INT64,
  judge_vi_naturalness INT64,
  judge_vi_preservation INT64,
  judge_exec_quality INT64,
  judge_avg FLOAT64,
  judge_issue STRING,
  judge_fix_suggestion STRING,
  verdict STRING,
  reviewed_at TIMESTAMP,
  det_traffic_claim_ok BOOL OPTIONS(description="Website traffic/session claims are backed by a WEBSITE sessions line in the facts block. Replaces the old blanket prohibition."),
  det_causal_claim_ok BOOL OPTIONS(description="No causal language attributing revenue to ad spend. roas_channel is an efficiency ratio, not incrementality.")
)
OPTIONS(
  description="Score card per AI generation. Deterministic checks are authoritative; judge scores are advisory."
);
