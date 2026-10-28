CREATE VIEW `marine-cycle-484213-b4.reportdb.dash_highlights`
AS WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),

wow AS (
  SELECT 'PAGE1_WOW' AS page, country, level_1, level_2,
         delta_nmv AS impact_vnd, pct_nmv AS pct_change,
         nmv_cur AS value_cur, nmv_prv AS value_ref,
         bills_cur, bills_prv, pct_bills, basket_cur, basket_prv, pct_basket,
         driver, diagnosis, diagnosis_source, action_trigger, traffic_note,
         IF(delta_nmv >= 0, 'HIGHLIGHT', 'LOWLIGHT') AS item_type
  FROM `marine-cycle-484213-b4.reportdb.dash_page1_wow`
  CROSS JOIN p
  WHERE ABS(delta_nmv) >= p.material_abs_vnd
    AND ABS(IFNULL(pct_nmv,0)) >= p.material_pct
),
mtd AS (
  SELECT 'PAGE2_MTD' AS page, country, level_1, level_2,
         gap_to_target AS impact_vnd,
         attainment_pct - 1 AS pct_change,
         mtd_actual_nmv AS value_cur, mtd_target AS value_ref,
         mtd_bills AS bills_cur, CAST(NULL AS INT64) AS bills_prv,
         CAST(NULL AS FLOAT64) AS pct_bills,
         mtd_basket AS basket_cur, CAST(NULL AS FLOAT64) AS basket_prv,
         CAST(NULL AS FLOAT64) AS pct_basket,
         CAST(NULL AS STRING) AS driver,
         CONCAT(target_status, ' - ', FORMAT('%.0f', attainment_pct*100), '% of MTD target') AS diagnosis,
         'derived' AS diagnosis_source,
         IF(target_status='MISS','Close the gap or re-forecast the month','Protect the run-rate') AS action_trigger,
         CAST(NULL AS STRING) AS traffic_note,
         IF(gap_to_target >= 0, 'HIGHLIGHT', 'LOWLIGHT') AS item_type
  FROM `marine-cycle-484213-b4.reportdb.dash_page2_mtd`
  CROSS JOIN p
  WHERE attainment_pct IS NOT NULL          -- suppressed rows can never headline
    AND ABS(gap_to_target) >= p.material_abs_vnd
),
u AS (SELECT * FROM wow UNION ALL SELECT * FROM mtd)
SELECT * EXCEPT(rn), rn AS rank_in_group
FROM (
  SELECT u.*, ROW_NUMBER() OVER (PARTITION BY page, item_type ORDER BY ABS(impact_vnd) DESC) AS rn
  FROM u
)
WHERE rn <= 3;
