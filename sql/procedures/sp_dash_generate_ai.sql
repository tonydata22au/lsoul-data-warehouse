CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.reportdb.sp_dash_generate_ai`(i_force BOOL)
BEGIN
  DECLARE v_pending INT64;

  CREATE OR REPLACE TEMP TABLE t_pending AS
  SELECT f.page, f.period_key, f.period_label, f.facts_hash, f.prompt, f.action_block
  FROM `marine-cycle-484213-b4.reportdb.v_dash_ai_facts` f
  LEFT JOIN `marine-cycle-484213-b4.reportdb.dash_ai_narrative` c
         ON c.page = f.page AND c.period_key = f.period_key
  WHERE IFNULL(i_force, FALSE)
     OR c.page IS NULL
     OR c.facts_hash IS DISTINCT FROM f.facts_hash
     OR c.gen_status <> 'OK';

  SET v_pending = (SELECT COUNT(*) FROM t_pending);
  IF v_pending = 0 THEN
    SELECT 'Cache hit - 0 model calls made.' AS run_note; RETURN;
  END IF;

  -- FIX 1: ceiling raised. Thinking (~11.2k) + answer (~3.1k) = ~14.3k measured.
  -- 32,768 leaves ~2.3x headroom for a longer point set or action block.
  CREATE OR REPLACE TEMP TABLE t_gen AS
  SELECT page, period_key, period_label, facts_hash,
    AI.GENERATE(
       prompt,
       connection_id => 'marine-cycle-484213-b4.asia-southeast1.agent_platform_ai',
       endpoint      => 'gemini-3.5-flash',
       model_params  => JSON '{"generation_config":{"max_output_tokens":50000,"temperature":0.4}}',
       output_schema => 'exec_summary_en STRING, exec_summary_vi STRING, highlights_en STRING, highlights_vi STRING, actions_vi STRING'
    ) AS g
  FROM t_pending;

  MERGE `marine-cycle-484213-b4.reportdb.dash_ai_narrative` t
  USING (
    WITH ev AS (
      SELECT t.page, t.period_key, t.period_label, t.facts_hash, t.g, p.action_block,
             JSON_VALUE(t.g.full_response, '$.candidates[0].finish_reason')  AS finish_reason,
             IFNULL(t.g.status, '')                                          AS api_status,
             CAST(JSON_VALUE(t.g.full_response,'$.usage_metadata.prompt_token_count')     AS INT64) AS prompt_tokens,
             CAST(JSON_VALUE(t.g.full_response,'$.usage_metadata.candidates_token_count') AS INT64) AS answer_tokens,
             CAST(JSON_VALUE(t.g.full_response,'$.usage_metadata.thoughts_token_count')   AS INT64) AS thinking_tokens
      FROM t_gen t JOIN t_pending p USING (page, period_key)
    )
    SELECT page, period_key, period_label, facts_hash
      ,g.exec_summary_en, g.exec_summary_vi
      -- FIX 4: a NULL action_block no longer nullifies a good narrative.
      ,CONCAT(g.highlights_en, '\n\nACTIONS:\n', IFNULL(action_block, ''))   AS narrative_en
      ,CONCAT(g.highlights_vi, '\n\nACTIONS:\n', IFNULL(g.actions_vi, ''))   AS narrative_vi
      ,'gemini-3.5-flash' AS model_endpoint
      ,prompt_tokens
      -- FIX 3: thinking tokens are billed as output and must be counted.
      ,IFNULL(answer_tokens, 0) + IFNULL(thinking_tokens, 0) AS output_tokens
      -- FIX 2: authoritative signals first. finish_reason distinguishes a token-ceiling
      -- failure from a model refusal; api_status catches any other parse/API failure.
      -- Neither was read before, so both were being reported as EMPTY_EXEC.
      ,CASE WHEN finish_reason = 'MAX_TOKENS'                     THEN 'TRUNCATED'
            WHEN finish_reason NOT IN ('STOP', 'MAX_TOKENS')      THEN CONCAT('BLOCKED_', finish_reason)
            WHEN api_status <> ''                                 THEN 'PARSE_FAIL'
            WHEN g.exec_summary_en IS NULL OR g.exec_summary_en = '' THEN 'EMPTY_EXEC'
            WHEN g.highlights_en   IS NULL OR g.highlights_en   = '' THEN 'EMPTY_EN'
            WHEN g.highlights_vi   IS NULL OR g.highlights_vi   = '' THEN 'EMPTY_VI'
            WHEN g.actions_vi      IS NULL OR g.actions_vi      = '' THEN 'EMPTY_ACTIONS_VI'
            ELSE 'OK' END AS gen_status
    FROM ev
  ) s
  ON t.page = s.page AND t.period_key = s.period_key
  WHEN MATCHED THEN UPDATE SET
     facts_hash = s.facts_hash, exec_summary_en = s.exec_summary_en,
     exec_summary_vi = s.exec_summary_vi, narrative_en = s.narrative_en,
     narrative_vi = s.narrative_vi, model_endpoint = s.model_endpoint,
     prompt_tokens = s.prompt_tokens, output_tokens = s.output_tokens,
     gen_status = s.gen_status, generated_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT
    (page, period_key, period_label, facts_hash, exec_summary_en, exec_summary_vi,
     narrative_en, narrative_vi, model_endpoint, prompt_tokens, output_tokens,
     gen_status, generated_at)
  VALUES
    (s.page, s.period_key, s.period_label, s.facts_hash, s.exec_summary_en, s.exec_summary_vi,
     s.narrative_en, s.narrative_vi, s.model_endpoint, s.prompt_tokens, s.output_tokens,
     s.gen_status, CURRENT_TIMESTAMP());

  -- N5: the MERGE above overwrites the previous attempt, so a failed generation left no
  -- trace once a retry replaced it - the only evidence was a pattern of NULLs in
  -- dash_ai_review. One appended row per attempt keeps the gen_status history.
  INSERT INTO `marine-cycle-484213-b4.reportdb.dash_ai_generation_log`
  (logged_at, page, period_key, facts_hash, finish_reason, api_status,
   prompt_tokens, answer_tokens, thinking_tokens, gen_status,
   len_exec_summary_en, len_narrative_en, len_narrative_vi)
  SELECT CURRENT_TIMESTAMP(), t.page, t.period_key, t.facts_hash
    ,JSON_VALUE(t.g.full_response, '$.candidates[0].finish_reason')
    ,IFNULL(t.g.status, '')
    ,CAST(JSON_VALUE(t.g.full_response,'$.usage_metadata.prompt_token_count')     AS INT64)
    ,CAST(JSON_VALUE(t.g.full_response,'$.usage_metadata.candidates_token_count') AS INT64)
    ,CAST(JSON_VALUE(t.g.full_response,'$.usage_metadata.thoughts_token_count')   AS INT64)
    ,n.gen_status
    ,LENGTH(IFNULL(n.exec_summary_en,''))
    ,LENGTH(IFNULL(n.narrative_en,''))
    ,LENGTH(IFNULL(n.narrative_vi,''))
  FROM t_gen t
  JOIN `marine-cycle-484213-b4.reportdb.dash_ai_narrative` n
    ON n.page = t.page AND n.period_key = t.period_key;

  SELECT FORMAT('Generated %d page narrative(s) with exec summary, EN + VI.', v_pending) AS run_note;
END;