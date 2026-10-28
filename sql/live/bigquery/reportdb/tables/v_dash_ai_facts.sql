CREATE VIEW `marine-cycle-484213-b4.reportdb.v_dash_ai_facts`
OPTIONS(
  description="Public interface over v_dash_ai_facts_core. Now passes the real guidance_version through instead of hard-coding 0."
)
AS SELECT page, period_label, period_key, facts_hash, prompt,
       facts_block, action_block, action_block_vi, action_block_sql,
       guidance_version
FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_facts_core`;
