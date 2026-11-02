CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.core_pancake.sp_pancake_core_warehouse_insert`()
BEGIN
  -- Maintain one current dimension row per warehouse ID. Names/codes are display attributes.
  -- Policy provenance and new-ID defaults: sql/config/warehouse_policy.json.
  -- The live 2026-11-02 baseline has no logging calls; keep that behavior.
  DECLARE data_proc_date DATE DEFAULT
    (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_inventory_histories`);

  BEGIN TRANSACTION;

  -- Do not silently multiply rows or discard duplicates already present in the target.
  ASSERT (
    SELECT COUNT(*) = COUNT(DISTINCT warehouse_id)
      AND COUNTIF(warehouse_id IS NULL OR TRIM(warehouse_id) = '') = 0
    FROM `marine-cycle-484213-b4.core_pancake.core_warehouse`
  ) AS 'core_warehouse requires unique, nonempty warehouse IDs before refresh';

  -- BEGIN WAREHOUSE POLICY
  CREATE OR REPLACE TEMP TABLE warehouse_policy AS
  SELECT '115e6258-72f0-468a-9743-731d06a771fa' AS warehouse_id, 'THAILAND' AS country, 'M' AS warehouse_type
  UNION ALL SELECT '133983a4-ff7d-4861-805c-0a1bdd51795f', 'THAILAND', 'P'
  UNION ALL SELECT '1a21d42d-d648-4fdd-9095-932fceb08a2d', 'VIETNAM', 'NONE'
  UNION ALL SELECT '28fc9c4c-6ad6-4dd3-8dda-bc44397c9e0f', 'VIETNAM', 'B'
  UNION ALL SELECT '3c86e018-936a-4f33-8dda-7a0ad4f038db', 'VIETNAM', 'B'
  UNION ALL SELECT '3fb24787-3208-4fb7-9580-24a3754e51d6', 'VIETNAM', 'P'
  UNION ALL SELECT '490ded40-64ba-4424-aaed-399abbf13fbb', 'THAILAND', 'P'
  UNION ALL SELECT '4a93fada-d892-4bbd-8547-ec505e6104df', 'VIETNAM', 'P'
  UNION ALL SELECT '66184c11-4f37-465b-b5a7-09cb026b9ebd', 'VIETNAM', 'M'
  UNION ALL SELECT '76be7836-6dc5-4b1c-9e48-b18e43127453', 'CHINA', 'B'
  UNION ALL SELECT '878504e9-fb75-4870-8504-b2ecdbc097ba', 'THAILAND', 'B'
  UNION ALL SELECT 'ad07f1c9-84be-4c4d-bc5b-4de980ffb97e', 'THAILAND', 'P'
  UNION ALL SELECT 'c8b7a738-7b1c-4599-ad32-64d145b005c1', 'VIETNAM', 'P'
  UNION ALL SELECT 'c9aea4ce-e71e-404e-b7c1-8d6ff342d748', 'VIETNAM', 'P'
  UNION ALL SELECT 'cf854971-c137-4e23-86ec-4bd8fbed6990', 'VIETNAM', 'P'
  UNION ALL SELECT 'd65e391f-711e-4f9d-81a4-ee54c2d7eca8', 'VIETNAM', 'P'
  UNION ALL SELECT 'e8d36467-0811-4020-a732-7e6564b5edb4', 'VIETNAM', 'P'
  UNION ALL SELECT 'eb66793a-2953-44da-8585-da8888111d6d', 'VIETNAM', 'B'
  UNION ALL SELECT 'f0eb59ac-aa0e-4cf6-971e-01456e5dc3d2', 'THAILAND', 'P';
  -- END WAREHOUSE POLICY

  IF data_proc_date = CURRENT_DATE('Asia/Ho_Chi_Minh') THEN
    -- Retain the latest nonblank observed name, then the existing name if this load has none.
    -- A load timestamp wins over event time; name and event ID settle equal timestamps.
    -- Activity is calculated across all observations, independently of name selection.
    -- BEGIN WAREHOUSE SOURCE
    CREATE OR REPLACE TEMP TABLE warehouse_source AS
    WITH observations AS (
      SELECT proc_date, inserted_at, inventory_history_id, warehouse_id, warehouse_name
      FROM `marine-cycle-484213-b4.stg_pancake.stg_inventory_histories`
      WHERE DATE(proc_date) = data_proc_date
        AND warehouse_id IS NOT NULL AND TRIM(warehouse_id) != ''
    ), activity AS (
      SELECT warehouse_id, MAX(DATE(inserted_at)) AS newest_history_date
      FROM observations
      GROUP BY warehouse_id
    ), names AS (
      SELECT warehouse_id, warehouse_name,
        ROW_NUMBER() OVER (
          PARTITION BY warehouse_id
          ORDER BY proc_date DESC, inserted_at DESC, warehouse_name ASC, inventory_history_id DESC
        ) AS name_rank
      FROM observations
      WHERE warehouse_name IS NOT NULL AND TRIM(warehouse_name) != ''
    )
    SELECT
      a.warehouse_id,
      CASE WHEN n.warehouse_name IS NULL THEN target.warehouse_code
        ELSE `marine-cycle-484213-b4.sysdb.udf_remove_vn_accents`(n.warehouse_name)
      END AS warehouse_code,
      COALESCE(n.warehouse_name, target.warehouse_name) AS warehouse_name,
      COALESCE(p.country, 'VIETNAM') AS country,
      COALESCE(p.warehouse_type, 'P') AS warehouse_type,
      CASE WHEN a.newest_history_date < DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        THEN 0 ELSE 1 END AS is_active,
      DATETIME(DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)) AS inserted_at,
      CURRENT_DATETIME('Asia/Ho_Chi_Minh') AS updated_at
    FROM activity AS a
    LEFT JOIN names AS n ON a.warehouse_id = n.warehouse_id AND n.name_rank = 1
    LEFT JOIN warehouse_policy AS p ON a.warehouse_id = p.warehouse_id
    LEFT JOIN `marine-cycle-484213-b4.core_pancake.core_warehouse` AS target
      ON a.warehouse_id = target.warehouse_id;
    -- END WAREHOUSE SOURCE

    -- BEGIN WAREHOUSE MERGE
    MERGE `marine-cycle-484213-b4.core_pancake.core_warehouse` AS target
    USING warehouse_source AS source ON target.warehouse_id = source.warehouse_id
    WHEN MATCHED THEN UPDATE SET
      warehouse_code = source.warehouse_code,
      warehouse_name = source.warehouse_name,
      country = source.country,
      warehouse_type = source.warehouse_type,
      is_active = source.is_active,
      inserted_at = source.inserted_at,
      updated_at = source.updated_at
    WHEN NOT MATCHED THEN INSERT (
      warehouse_id, warehouse_code, warehouse_name, country, warehouse_type,
      is_active, inserted_at, updated_at
    ) VALUES (
      source.warehouse_id, source.warehouse_code, source.warehouse_name, source.country,
      source.warehouse_type, source.is_active, source.inserted_at, source.updated_at
    );
    -- END WAREHOUSE MERGE
  END IF;

  -- Correct renamed and inactive warehouses even when absent from today's source partition.
  -- The source merge defaults unknown IDs to VIETNAM/P; this correction leaves unknown IDs untouched.
  -- BEGIN WAREHOUSE CLASSIFICATION
  UPDATE `marine-cycle-484213-b4.core_pancake.core_warehouse` AS target
  SET country = p.country,
      warehouse_type = p.warehouse_type,
      updated_at = CURRENT_DATETIME('Asia/Ho_Chi_Minh')
  FROM warehouse_policy AS p
  WHERE target.warehouse_id = p.warehouse_id
    AND (target.country IS DISTINCT FROM p.country
      OR target.warehouse_type IS DISTINCT FROM p.warehouse_type);
  -- END WAREHOUSE CLASSIFICATION

  -- Preserve the existing UTC-date 30-day activity cutoff, including no-history behavior.
  -- BEGIN WAREHOUSE ACTIVITY
  UPDATE `marine-cycle-484213-b4.core_pancake.core_warehouse`
  SET is_active = 0,
      updated_at = CURRENT_DATETIME('Asia/Ho_Chi_Minh')
  WHERE is_active = 1 AND warehouse_id IN (
    SELECT i.warehouse_id
    FROM `marine-cycle-484213-b4.core_pancake.core_inventory_histories` AS i
    GROUP BY i.warehouse_id
    HAVING IFNULL(DATE_DIFF(CURRENT_DATE(), MAX(DATE(i.inserted_at)), DAY), 0) > 30
  );
  -- END WAREHOUSE ACTIVITY

  COMMIT TRANSACTION;
END;
