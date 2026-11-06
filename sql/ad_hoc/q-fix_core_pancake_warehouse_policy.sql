-- Corrective UPDATE for the old live table core_pancake.core_warehouse (decision D6, 2026-11-05).
-- PREPARED, NOT RUN: writes production. Run once, with the owner's approval, after deploying the
-- policy-aware sql/procedures/core_pancake.sp_pancake_core_warehouse_insert.sql (which keeps rows
-- corrected from then on). Values are sql/config/warehouse_policy.json (verified 2026-11-02);
-- regenerate this file if that file changes. Decisions D2 (name prefix decides country) and D3
-- (480F = B, TH Office = M, VN Marketing = M, VN Defective = NONE) are tested in
-- tests/test_warehouse_policy_prefix.py.
--
-- Read-only check on 2026-11-05: 7 rows differ (CN/TH Backup Stock, TH EmSphere Store and
-- TH Office Stock had VIETNAM; 480F, Defective and Marketing Stock had P). core.core_pancake__warehouse
-- already matches. Re-running changes nothing (only differing rows are updated).

BEGIN TRANSACTION;

UPDATE `marine-cycle-484213-b4.core_pancake.core_warehouse` AS core
SET
  country = policy.country,
  warehouse_type = policy.warehouse_type,
  updated_at = CURRENT_DATETIME('Asia/Ho_Chi_Minh')
FROM UNNEST([STRUCT<warehouse_id STRING, country STRING, warehouse_type STRING>
  ('115e6258-72f0-468a-9743-731d06a771fa', 'THAILAND', 'M'),
  ('133983a4-ff7d-4861-805c-0a1bdd51795f', 'THAILAND', 'P'),
  ('1a21d42d-d648-4fdd-9095-932fceb08a2d', 'VIETNAM', 'NONE'),
  ('28fc9c4c-6ad6-4dd3-8dda-bc44397c9e0f', 'VIETNAM', 'B'),
  ('3c86e018-936a-4f33-8dda-7a0ad4f038db', 'VIETNAM', 'B'),
  ('3fb24787-3208-4fb7-9580-24a3754e51d6', 'VIETNAM', 'P'),
  ('490ded40-64ba-4424-aaed-399abbf13fbb', 'THAILAND', 'P'),
  ('4a93fada-d892-4bbd-8547-ec505e6104df', 'VIETNAM', 'P'),
  ('66184c11-4f37-465b-b5a7-09cb026b9ebd', 'VIETNAM', 'M'),
  ('76be7836-6dc5-4b1c-9e48-b18e43127453', 'CHINA', 'B'),
  ('878504e9-fb75-4870-8504-b2ecdbc097ba', 'THAILAND', 'B'),
  ('ad07f1c9-84be-4c4d-bc5b-4de980ffb97e', 'THAILAND', 'P'),
  ('c8b7a738-7b1c-4599-ad32-64d145b005c1', 'VIETNAM', 'P'),
  ('c9aea4ce-e71e-404e-b7c1-8d6ff342d748', 'VIETNAM', 'P'),
  ('cf854971-c137-4e23-86ec-4bd8fbed6990', 'VIETNAM', 'P'),
  ('d65e391f-711e-4f9d-81a4-ee54c2d7eca8', 'VIETNAM', 'P'),
  ('e8d36467-0811-4020-a732-7e6564b5edb4', 'VIETNAM', 'P'),
  ('eb66793a-2953-44da-8585-da8888111d6d', 'VIETNAM', 'B'),
  ('f0eb59ac-aa0e-4cf6-971e-01456e5dc3d2', 'THAILAND', 'P')
]) AS policy
WHERE core.warehouse_id = policy.warehouse_id
  AND (core.country IS DISTINCT FROM policy.country
       OR core.warehouse_type IS DISTINCT FROM policy.warehouse_type);

ASSERT @@row_count <= 7 AS 'expected at most the 7 rows found on 2026-11-05; re-check before committing';

COMMIT TRANSACTION;
