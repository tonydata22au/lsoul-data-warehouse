CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4`.reportdb.sp_dash_review_ai(i_attempt_no INT64)
BEGIN
  DECLARE v_gver INT64 DEFAULT (
    SELECT IFNULL(MAX(guidance_version), 0)
    FROM `marine-cycle-484213-b4.reportdb.dash_ai_guidance` WHERE is_active);

  DECLARE array_point_id ARRAY<STRING> DEFAULT (
    SELECT ARRAY_AGG(point_id)
    FROM `marine-cycle-484213-b4.reportdb.dash_material_points`);

  CREATE OR REPLACE TEMP TABLE t_pair AS
  SELECT
     n.page, n.period_key, n.facts_hash
    ,n.narrative_en, n.narrative_vi
    ,n.exec_summary_en, n.exec_summary_vi
    ,f.facts_block, f.action_block
    ,ps.headline_note
    -- strip alphanumeric codes so SKUs are never mistaken for figures
    -- exec summary is checked for numeric fidelity too: it is the part the board reads
    ,REGEXP_REPLACE(CONCAT(IFNULL(n.narrative_en,''),' ',IFNULL(n.narrative_vi,''),' ',
                           IFNULL(n.exec_summary_en,''),' ',IFNULL(n.exec_summary_vi,'')),
        r'[A-Za-z]+[0-9]+[A-Za-z0-9\-]*', ' ') AS nar_clean
    ,REGEXP_REPLACE(CONCAT(IFNULL(f.facts_block,''),' ',IFNULL(f.action_block,'')),
        r'[A-Za-z]+[0-9]+[A-Za-z0-9\-]*', ' ') AS fac_clean
  FROM `marine-cycle-484213-b4.reportdb.dash_ai_narrative` n
  JOIN `marine-cycle-484213-b4.reportdb.v_dash_ai_facts` f
    ON f.page = n.page AND f.period_key = n.period_key
  LEFT JOIN `marine-cycle-484213-b4.reportdb.dash_page_summary` ps
    ON ps.page = n.page;

  CREATE OR REPLACE TEMP TABLE t_det AS
  SELECT p.*,
    ARRAY(SELECT x FROM UNNEST(
        ARRAY(SELECT DISTINCT IF(LTRIM(a,'0')='','0',LTRIM(a,'0'))
              FROM UNNEST(REGEXP_EXTRACT_ALL(p.nar_clean, r'[0-9]+(?:\.[0-9]+)?')) a)) x
      WHERE x NOT IN UNNEST(
        ARRAY(SELECT DISTINCT IF(LTRIM(b,'0')='','0',LTRIM(b,'0'))
              FROM UNNEST(REGEXP_EXTRACT_ALL(p.fac_clean, r'[0-9]+(?:\.[0-9]+)?')) b))
    ) AS unsupported_numbers
  FROM t_pair p;

  CREATE OR REPLACE TEMP TABLE t_scored AS
  SELECT
     d.*
    ,ARRAY_LENGTH(d.unsupported_numbers) = 0 AS det_numeric_ok
    -- every [Owner] tag in the English actions must survive into Vietnamese
    ,ARRAY_LENGTH(REGEXP_EXTRACT_ALL(d.action_block,  r'\[[^\]]+\]'))
     = ARRAY_LENGTH(REGEXP_EXTRACT_ALL(d.narrative_vi, r'\[[^\]]+\]')) AS det_owner_tags_ok
    ,ARRAY_LENGTH(REGEXP_EXTRACT_ALL(d.narrative_en, r'\[[^\]]+\]'))
     = ARRAY_LENGTH(REGEXP_EXTRACT_ALL(d.narrative_vi, r'\[[^\]]+\]')) AS det_action_count_ok
    -- SKU codes named in the actions must appear in the Vietnamese too
    ,(SELECT LOGICAL_AND(REGEXP_CONTAINS(d.narrative_vi, sku))
      FROM UNNEST(IFNULL(REGEXP_EXTRACT_ALL(d.action_block, r'\b[A-Z][0-9]{6,}[0-9A-Z\-]*\b'), [])) sku)
      IS NOT FALSE AS det_sku_ok
    ,REGEXP_CONTAINS(d.narrative_vi,
      r'[àáâãèéêìíòóôõùúýăđĩũơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ]') AS det_diacritics_ok
    ,ARRAY_LENGTH(REGEXP_EXTRACT_ALL(d.narrative_en, r'\*\*(Highlight|Lowlight) -\*\*'))
     = ARRAY_LENGTH(REGEXP_EXTRACT_ALL(d.narrative_vi, r'\*\*(Highlight|Lowlight) -\*\*')) AS det_headings_ok

    -- FOOTFALL is still impossible. No source instruments a physical store, so a
    -- claim that store visits moved is fabrication whatever else is supplied.
    ,NOT REGEXP_CONTAINS(LOWER(SPLIT(d.narrative_en, 'ACTIONS:')[OFFSET(0)]),
        r'footfall (rose|fell|increased|declined|dropped|grew|was up|was down)|store (traffic|visits) (rose|fell|increased|declined|dropped|grew)')
      AS det_no_traffic_claim

    -- WEBSITE traffic may now be discussed, but only where the facts block
    -- actually carried sessions. If the model asserts a traffic movement and the
    -- prompt never supplied one, that is still an invention.
    ,(NOT REGEXP_CONTAINS(LOWER(SPLIT(d.narrative_en, 'ACTIONS:')[OFFSET(0)]),
         r'\b(traffic|sessions|visits|visitors)\b[^.]{0,40}\b(rose|fell|increased|declined|dropped|grew|up|down)\b')
      OR REGEXP_CONTAINS(d.facts_block, r'WEBSITE sessions'))
      AS det_traffic_claim_ok

    -- roas_channel is an efficiency ratio, not incrementality. The ads sources
    -- attribute by channel and day, so "spend drove revenue" is a causal claim
    -- the data cannot support.
    ,NOT REGEXP_CONTAINS(LOWER(CONCAT(IFNULL(d.narrative_en,''),' ',IFNULL(d.exec_summary_en,''))),
        r'\b(spend|spending|advertising|ad spend|ads|paid media|campaigns?)\b[^.]{0,40}\b(drove|driving|generated|delivered|produced|caused|resulted in)\b')
      AS det_causal_claim_ok

    -- Exec summary present, and 3-5 sentences of ANALYSIS.
    -- The mandatory headline caveat is itself ~3 sentences and the prompt requires it
    -- verbatim, so counting it against a 3-5 budget failed the model for obeying two
    -- rules at once. Measured: PAGE2_MTD ran 6 sentences, 3 of them the caveat.
    -- The caveat is therefore stripped before counting, and the ceiling raised to 6
    -- so a legitimate 5-sentence summary plus a trailing clause is not rejected.
    ,(d.exec_summary_en IS NOT NULL AND d.exec_summary_en <> ''
      AND d.exec_summary_vi IS NOT NULL AND d.exec_summary_vi <> ''
      AND ARRAY_LENGTH(REGEXP_EXTRACT_ALL(
            TRIM(REPLACE(d.exec_summary_en, IFNULL(d.headline_note,'~~none~~'), '')),
            r'[.!?](?:\s|$)')) BETWEEN 3 AND 6) AS det_exec_summary_ok
    -- CONSISTENCY. Full coverage is required of the NARRATIVE, which has room for
    -- every point. Requiring it of the exec summary too was unsatisfiable: 7 material
    -- points cannot be cited inside 3-5 sentences without turning the summary into a
    -- list, which is the opposite of what a board summary is for. The summary is
    -- instead held to a weaker, achievable rule - it must cite at least the top 3
    -- points by absolute impact - checked as missing_from_summary (advisory).
    ,ARRAY(SELECT mp.point_id FROM `marine-cycle-484213-b4.reportdb.dash_material_points` mp
           WHERE NOT REGEXP_CONTAINS(IFNULL(d.narrative_en,''), mp.point_id)) AS missing_points
    ,ARRAY(SELECT mp.point_id FROM (
             SELECT point_id FROM `marine-cycle-484213-b4.reportdb.dash_material_points`
             ORDER BY ABS(delta_nmv) DESC LIMIT 3) mp
           WHERE NOT REGEXP_CONTAINS(IFNULL(d.exec_summary_en,''), mp.point_id)) AS missing_from_summary
    -- now matches the M-series too; an invented M04 used to slip through
    ,ARRAY(SELECT DISTINCT x FROM UNNEST(REGEXP_EXTRACT_ALL(
             CONCAT(IFNULL(d.exec_summary_en,''),' ',IFNULL(d.narrative_en,'')), r'\b[PM][0-9]{2}\b')) x
           WHERE x NOT IN UNNEST(array_point_id)) AS fabricated_points
  FROM t_det d;

  -- One judge call per page. Style dimensions only; no authority over numbers.
  CREATE OR REPLACE TEMP TABLE t_judge AS
  SELECT s.page, s.period_key,
    AI.GENERATE(CONCAT(
'You are a strict QA reviewer for bilingual retail commentary. Score the CANDIDATE against the FACTS.\n',
'Be harsh. Deduct for any drift. Score 1-5 each, integers only.\n\n',
'numeric_fidelity: every figure traceable to FACTS, none invented.\n',
'shape_adherence: each item names country + channel, the percent AND absolute move, then the driver\n',
'  metric with its own percent. Deduct heavily if it is a comma-separated data dump, not a sentence.\n',
'diagnosis_fidelity: uses the supplied diagnosis and invents no other cause. Website traffic and\n',
'  paid-media figures MAY be used where the FACTS supply them, and only there. Deduct heavily if the\n',
'  candidate (a) claims footfall or store visits moved - no store is instrumented, (b) discusses\n',
'  traffic or spend for a channel the FACTS do not list, or (c) says spend drove, generated or\n',
'  delivered revenue: roas_channel is an efficiency ratio, not proof of cause.\n',
'vi_naturalness: reads as professional Vietnamese retail / e-commerce reporting, not literal translation.\n',
'vi_preservation: headings, channel names, store names, SKU codes and [Owner] tags left in English exactly.\n',
'issues: max 25 words naming the single biggest flaw, or "none".\n',
'fix_suggestion: max 25 words, ONE concrete instruction that would improve the NEXT generation.\n',
'  It must be a style or emphasis instruction. Never suggest relaxing a rule. Or "none".\n\n',
'exec_quality: the executive summary must run 3-5 sentences covering, IN ORDER, (a) week over\n',
'  week, (b) month to date, (c) target progress with pace. Deduct if the order is wrong, if a\n',
'  section is missing, or if pace is stated against the pro-rated MTD target instead of the\n',
'  full-month target. If any M## marketing point exists, deduct if paid media is never mentioned.\n\n',
'FACTS:\n', s.facts_block,
'\n\nACTIONS_SOURCE - deterministic. This block is built by dash_action_items and appended to the\n',
'candidate AFTER generation. The model did not write it; it only translated it into Vietnamese.\n',
'Treat every figure, store name and SKU code below as ground truth - never score it as invented.\n',
'Score numeric_fidelity on whether the Vietnamese preserves these values faithfully:\n',
IFNULL(s.action_block,'(none)'),
'\n\nCANDIDATE_EXEC_SUMMARY_EN:\n', IFNULL(s.exec_summary_en,'(missing)'),
'\n\nCANDIDATE_EXEC_SUMMARY_VI:\n', IFNULL(s.exec_summary_vi,'(missing)'),
'\n\nCANDIDATE_EN:\n', s.narrative_en, '\n\nCANDIDATE_VI:\n', s.narrative_vi),
      connection_id => 'marine-cycle-484213-b4.asia-southeast1.agent_platform_ai',
      endpoint      => 'gemini-3.5-flash',
      model_params  => JSON '{"generation_config":{"max_output_tokens":32768,"temperature":0.3}}',
      output_schema => 'numeric_fidelity INT64, shape_adherence INT64, diagnosis_fidelity INT64, vi_naturalness INT64, vi_preservation INT64, exec_quality INT64, issues STRING, fix_suggestion STRING'
    ) AS j
  FROM t_scored s;

  -- explicit column list: the table now has more columns than the old positional
  -- INSERT assumed, and a positional insert would silently misalign after any
  -- future ADD COLUMN
  INSERT INTO `marine-cycle-484213-b4.reportdb.dash_ai_review` (
     review_id, page, period_key, facts_hash, attempt_no, guidance_version,
     unsupported_numbers,
     det_numeric_ok, det_owner_tags_ok, det_action_count_ok, det_sku_ok,
     det_diacritics_ok, det_headings_ok, det_no_traffic_claim,
     det_traffic_claim_ok, det_causal_claim_ok,
     det_exec_summary_ok, det_consistency_ok,
     missing_points, missing_from_summary, fabricated_points, det_pass,
     judge_numeric_fidelity, judge_shape_adherence, judge_diagnosis_fidelity,
     judge_vi_naturalness, judge_vi_preservation, judge_exec_quality,
     judge_avg, judge_issue, judge_fix_suggestion, verdict, reviewed_at)
  SELECT
     GENERATE_UUID()
    ,s.page, s.period_key, s.facts_hash
    ,IFNULL(i_attempt_no, 1)
    ,v_gver
    ,s.unsupported_numbers
    ,s.det_numeric_ok, s.det_owner_tags_ok, s.det_action_count_ok, s.det_sku_ok
    ,s.det_diacritics_ok, s.det_headings_ok, s.det_no_traffic_claim
    ,s.det_traffic_claim_ok, s.det_causal_claim_ok
    ,s.det_exec_summary_ok
    -- Blocking: full narrative coverage + no invented IDs. missing_from_summary is
    -- advisory and deliberately NOT in this gate.
    ,ARRAY_LENGTH(s.missing_points) = 0 AND ARRAY_LENGTH(s.fabricated_points) = 0 AS det_consistency_ok
    ,s.missing_points, s.missing_from_summary, s.fabricated_points
    ,IFNULL(s.det_numeric_ok AND s.det_owner_tags_ok AND s.det_action_count_ok AND s.det_sku_ok
      AND s.det_diacritics_ok AND s.det_headings_ok AND s.det_no_traffic_claim
      AND s.det_traffic_claim_ok AND s.det_causal_claim_ok
      AND s.det_exec_summary_ok
      AND ARRAY_LENGTH(s.missing_points) = 0 AND ARRAY_LENGTH(s.fabricated_points) = 0, FALSE) AS det_pass
    ,j.j.numeric_fidelity, j.j.shape_adherence, j.j.diagnosis_fidelity
    ,j.j.vi_naturalness, j.j.vi_preservation, j.j.exec_quality
    ,ROUND((j.j.numeric_fidelity + j.j.shape_adherence + j.j.diagnosis_fidelity
          + j.j.vi_naturalness + j.j.vi_preservation + j.j.exec_quality) / 6.0, 2)
    ,j.j.issues, j.j.fix_suggestion
    ,CASE
       WHEN NOT IFNULL(s.det_numeric_ok AND s.det_owner_tags_ok AND s.det_action_count_ok AND s.det_sku_ok
                 AND s.det_diacritics_ok AND s.det_headings_ok AND s.det_no_traffic_claim
                 AND s.det_traffic_claim_ok AND s.det_causal_claim_ok
                 AND s.det_exec_summary_ok
                 AND ARRAY_LENGTH(s.missing_points) = 0 AND ARRAY_LENGTH(s.fabricated_points) = 0, FALSE)
         THEN IF(IFNULL(i_attempt_no,1) >= 2, 'QUARANTINE', 'RETRY')
       -- N2: the judge call can itself fail - it ran at max_output_tokens 5000 on a thinking
       -- model, the same defect that broke the generator. NULL scores fell through every
       -- comparison below and landed on 'PUBLISH', so a judge that never answered was
       -- indistinguishable from one that approved. The deterministic gate above already covers
       -- numbers, coverage and VI structure, so the page still publishes - but under a verdict
       -- that says out loud that nothing judged it.
       WHEN j.j.shape_adherence IS NULL OR j.j.vi_naturalness IS NULL
         THEN 'PUBLISH_UNJUDGED'
       -- judge score is advisory: a low style score never blocks publication on its own,
       -- it only asks for one retry, and only on the first attempt.
       WHEN (j.j.shape_adherence + j.j.vi_naturalness) / 2.0 < 3 AND IFNULL(i_attempt_no,1) < 2
         THEN 'RETRY'
       ELSE 'PUBLISH'
     END
    ,CURRENT_TIMESTAMP()
  FROM t_scored s
  JOIN t_judge j ON j.page = s.page AND j.period_key = s.period_key;

  SELECT page, det_pass, det_consistency_ok, det_traffic_claim_ok, det_causal_claim_ok,
         missing_points, missing_from_summary,
         fabricated_points, judge_avg, verdict, unsupported_numbers, judge_issue
  FROM `marine-cycle-484213-b4.reportdb.dash_ai_review`
  WHERE reviewed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 MINUTE)
  ORDER BY page;
END;
