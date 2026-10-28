CREATE VIEW `marine-cycle-484213-b4.reportdb.v_ai_report_prompts`
AS SELECT * FROM `marine-cycle-484213-b4.reportdb.v_mtd_prompt`
UNION ALL
SELECT * FROM `marine-cycle-484213-b4.reportdb.v_wow_prompt`;
