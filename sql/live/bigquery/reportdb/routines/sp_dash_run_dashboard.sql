CREATE PROCEDURE `marine-cycle-484213-b4`.reportdb.sp_dash_run_dashboard()
BEGIN
  -- N7: every "what happened in this run" lookup below is scoped to v_t0, the moment this
  -- procedure started, instead of CURRENT_TIMESTAMP() - 10 MINUTE. The old wall-clock window
  -- was already the same order as the run's own wall time (595 s on 2026-09-06 12:09), so a
  -- slow run could lose its own attempt-1 verdicts and an overlapping run could pick up
  -- another run's. It also spanned every page at once, with no run identifier.
  DECLARE v_t0      TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE v_retry   INT64;
  DECLARE v_bad_gen INT64;

  CALL `marine-cycle-484213-b4.reportdb.sp_dash_generate_ai`(FALSE);

  -- F4: a generation that returned no usable text is a generator fault, not a content fault.
  -- Reviewing it spends a judge call and then records "material points missing from the
  -- narrative", which reads as a model quality problem and sent every diagnosis down the
  -- wrong path. Regenerate once before any review runs. Scoped to the periods currently
  -- being served, so historical rows left at a non-OK status never re-trigger this.
  SET v_bad_gen = (
    SELECT COUNT(*)
    FROM `marine-cycle-484213-b4.reportdb.dash_ai_narrative` n
    JOIN `marine-cycle-484213-b4.reportdb.v_dash_ai_facts` f
      ON f.page = n.page AND f.period_key = n.period_key
    WHERE n.gen_status <> 'OK');

  IF v_bad_gen > 0 THEN
    CALL `marine-cycle-484213-b4.reportdb.sp_dash_generate_ai`(FALSE);
  END IF;

  CALL `marine-cycle-484213-b4.reportdb.sp_dash_review_ai`(1);

  SET v_retry = (
    SELECT COUNT(*) FROM `marine-cycle-484213-b4.reportdb.dash_ai_review` r
    WHERE r.attempt_no = 1 AND r.verdict = 'RETRY' AND r.reviewed_at >= v_t0);

  IF v_retry > 0 THEN
    -- mark the failing pages stale so the generator re-runs only those
    UPDATE `marine-cycle-484213-b4.reportdb.dash_ai_narrative` n
    SET gen_status = 'RETRY_REQUIRED'
    WHERE EXISTS (
      SELECT 1 FROM `marine-cycle-484213-b4.reportdb.dash_ai_review` r
      WHERE r.page = n.page AND r.period_key = n.period_key
        AND r.attempt_no = 1 AND r.verdict = 'RETRY'
        AND r.reviewed_at >= v_t0);

    CALL `marine-cycle-484213-b4.reportdb.sp_dash_generate_ai`(FALSE);
    CALL `marine-cycle-484213-b4.reportdb.sp_dash_review_ai`(2);
  END IF;

  -- Stage the judge's suggestion as PROPOSED. It does NOT activate itself.
  -- N2/N3: skip rows where the judge never answered (judge_avg NULL would round to a NULL
  -- rating), and use an explicit column list - dash_ai_feedback is positional-insert bait.
  INSERT INTO `marine-cycle-484213-b4.reportdb.dash_ai_feedback`
    (feedback_id, submitted_by, submitted_at, page, period_key, rating, feedback_text,
     proposed_guidance, source, status, screen_flag, reviewed_by, reviewed_at)
  SELECT GENERATE_UUID(), 'auto-judge', CURRENT_TIMESTAMP(), r.page, r.period_key,
         CAST(ROUND(r.judge_avg) AS INT64),
         CONCAT('Auto-review issue: ', IFNULL(r.judge_issue,'none')),
         r.judge_fix_suggestion, 'JUDGE', 'PROPOSED',
         'Model-proposed. Review before approving: a prompt that edits itself can drift.',
         NULL, NULL
  FROM `marine-cycle-484213-b4.reportdb.dash_ai_review` r
  WHERE r.reviewed_at >= v_t0
    AND IFNULL(r.judge_fix_suggestion,'none') NOT IN ('none','None','')
    AND r.judge_avg IS NOT NULL
    AND r.judge_avg < 4.5
    AND NOT EXISTS (
      SELECT 1 FROM `marine-cycle-484213-b4.reportdb.dash_ai_feedback` f
      WHERE f.proposed_guidance = r.judge_fix_suggestion);

  SELECT page, attempt_no, det_pass, judge_avg, verdict, unsupported_numbers, judge_issue
  FROM `marine-cycle-484213-b4.reportdb.dash_ai_review`
  WHERE reviewed_at >= v_t0
  ORDER BY page, attempt_no;
END;
