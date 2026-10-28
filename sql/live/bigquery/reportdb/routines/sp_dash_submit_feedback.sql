CREATE PROCEDURE `marine-cycle-484213-b4`.reportdb.sp_dash_submit_feedback(i_submitted_by STRING, i_page STRING, i_period_key STRING, i_rating INT64, i_feedback_text STRING, i_proposed_guidance STRING)
OPTIONS(
  description="Records feedback as PROPOSED. Never activates it. Screens for attempts to relax the hard rules or inject instructions.")
BEGIN
  DECLARE v_flag STRING DEFAULT NULL;

  -- Tripwire for guidance that would relax an integrity rule or inject instructions.
  IF REGEXP_CONTAINS(LOWER(IFNULL(i_proposed_guidance,'')),
       r'ignore (previous|prior|the|all)|disregard|override|regardless of|you may (invent|estimate|assume)|make up|fabricat|do not mention|omit the (caveat|note|exclusion)|hide the|traffic (rose|fell|increased)|system prompt|new instruction')
  THEN
    SET v_flag = 'FLAGGED: appears to relax a hard rule or inject instructions. Approve only after reading the full text.';
  ELSEIF LENGTH(IFNULL(i_proposed_guidance,'')) > 200 THEN
    SET v_flag = 'FLAGGED: over 200 chars. Guidance must be one short instruction.';
  END IF;

  INSERT INTO `marine-cycle-484213-b4.reportdb.dash_ai_feedback`
  VALUES (GENERATE_UUID(), i_submitted_by, CURRENT_TIMESTAMP(), i_page, i_period_key,
          i_rating, i_feedback_text, i_proposed_guidance, 'HUMAN', 'PROPOSED',
          v_flag, NULL, NULL);

  SELECT IFNULL(v_flag, 'Recorded as PROPOSED. It will not affect any run until approved.') AS result;
END;
