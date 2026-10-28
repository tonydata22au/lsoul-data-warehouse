CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4`.reportdb.sp_dash_approve_guidance(i_feedback_id STRING, i_reviewed_by STRING, i_approve BOOL)
OPTIONS(
  description="Approves or rejects a PROPOSED feedback line. Approval activates it as guidance under a new version number.")
BEGIN
  DECLARE v_text STRING;
  DECLARE v_page STRING;
  DECLARE v_active INT64;
  DECLARE v_next_ver INT64;

  SET (v_text, v_page) = (
    SELECT AS STRUCT proposed_guidance, page
    FROM `marine-cycle-484213-b4.reportdb.dash_ai_feedback`
    WHERE feedback_id = i_feedback_id AND status = 'PROPOSED' LIMIT 1);

  IF v_text IS NULL THEN
    SELECT 'No PROPOSED feedback with that id.' AS result; RETURN;
  END IF;

  UPDATE `marine-cycle-484213-b4.reportdb.dash_ai_feedback`
  SET status = IF(i_approve,'APPROVED','REJECTED'),
      reviewed_by = i_reviewed_by, reviewed_at = CURRENT_TIMESTAMP()
  WHERE feedback_id = i_feedback_id;

  IF NOT i_approve THEN
    SELECT 'Rejected. Nothing changed in the prompt.' AS result; RETURN;
  END IF;

  SET v_active = (SELECT COUNT(*) FROM `marine-cycle-484213-b4.reportdb.dash_ai_guidance` WHERE is_active);
  IF v_active >= 10 THEN
    SELECT 'Approved, but NOT activated: 10 active guidance lines already. Retire one first (see v_dash_ai_quality).' AS result;
    RETURN;
  END IF;

  SET v_next_ver = (SELECT IFNULL(MAX(guidance_version),0)+1
                    FROM `marine-cycle-484213-b4.reportdb.dash_ai_guidance`);

  INSERT INTO `marine-cycle-484213-b4.reportdb.dash_ai_guidance`
  VALUES (GENERATE_UUID(), v_next_ver, v_page, v_text, i_feedback_id,
          TRUE, CURRENT_TIMESTAMP(), NULL, NULL);

  -- force regeneration: the prompt has changed, so the cache is stale
  UPDATE `marine-cycle-484213-b4.reportdb.dash_ai_narrative`
  SET facts_hash = CONCAT('STALE_', facts_hash)
  WHERE page = v_page OR v_page = 'BOTH';

  SELECT FORMAT('Activated as guidance version %d. Narratives marked stale and will regenerate on the next run.', v_next_ver) AS result;
END;
