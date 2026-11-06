-- Read-only drift check: the dbt sale-end seed vs the live Dataform sale-end list.
--
-- Source of truth today: the ppl-pancake Dataform operation `definitions/query_1781833889494.sql`
-- (workflow `ppl_pancake_product`, 07:45 Asia/Ho_Chi_Minh). It runs
--   UPDATE core_pancake.core_product SET product_tags = 'SYS_01_SALE_END,TO_REVIEW' WHERE display_id IN (...)
-- The dbt model core.core_pancake__product reads the same list from the seed
-- lsoul_dbt/seeds/pancake/pancake_sale_end_display_ids.csv (loaded to dbt_seeds by the daily build).
--
-- This query takes the ID list from the latest successful UPDATE job of that operation
-- (INFORMATION_SCHEMA.JOBS_BY_PROJECT, last 7 days) and compares it with the loaded seed table.
-- Expected: one row `in_sync` with live_only = 0 and seed_only = 0.
-- `live_only` > 0: the list grew; copy the new IDs into the seed CSV (sorted, de-duplicated),
--   then (owner approval) `dbt seed -s pancake_sale_end_display_ids` and a full refresh of core_pancake__product.
-- `no_recent_update_job`: the Dataform operation did not run in 7 days (paused or retired).
--   Then the seed is the only list; check it against the owner's list by hand.
-- Rows with display IDs are product codes, not personal data. Cost: one JOBS scan plus a ~4k-row seed.
-- Verified 2026-11-06: 3,568 = 3,568 IDs, in sync (tasks/core-pancake-repoint-t7-report.md).
WITH latest_job AS (
  SELECT job_id, creation_time, query
  FROM `marine-cycle-484213-b4`.`region-asia-southeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND statement_type = 'UPDATE'
    AND state = 'DONE' AND error_result IS NULL
    AND REGEXP_CONTAINS(query, r'core_pancake\.core_product')
    AND REGEXP_CONTAINS(query, r"SET\s+product_tags\s*=\s*'SYS_01_SALE_END,TO_REVIEW'")
  QUALIFY ROW_NUMBER() OVER (ORDER BY creation_time DESC) = 1
), live AS (
  SELECT DISTINCT TRIM(id) AS display_id
  FROM latest_job,
    UNNEST(REGEXP_EXTRACT_ALL(REGEXP_EXTRACT(query, r'(?is)\bIN\s*\((.*)\)'), r"'([^']+)'")) AS id
), seed AS (
  SELECT DISTINCT TRIM(display_id) AS display_id
  FROM `marine-cycle-484213-b4.dbt_seeds.pancake_sale_end_display_ids`
), diff AS (
  SELECT 'live_only' AS side, display_id FROM live WHERE display_id NOT IN (SELECT display_id FROM seed)
  UNION ALL
  SELECT 'seed_only', display_id FROM seed WHERE display_id NOT IN (SELECT display_id FROM live)
)
SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM latest_job) = 0 THEN 'no_recent_update_job'
    WHEN (SELECT COUNT(*) FROM diff) = 0 THEN 'in_sync'
    ELSE 'drift'
  END AS finding,
  (SELECT ANY_VALUE(creation_time) FROM latest_job) AS live_job_time,
  (SELECT COUNT(*) FROM live) AS live_ids,
  (SELECT COUNT(*) FROM seed) AS seed_ids,
  (SELECT COUNTIF(side = 'live_only') FROM diff) AS live_only,
  (SELECT COUNTIF(side = 'seed_only') FROM diff) AS seed_only,
  (SELECT ARRAY_AGG(display_id ORDER BY display_id LIMIT 50) FROM diff WHERE side = 'live_only') AS live_only_sample,
  (SELECT ARRAY_AGG(display_id ORDER BY display_id LIMIT 50) FROM diff WHERE side = 'seed_only') AS seed_only_sample
