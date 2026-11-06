-- Read-only preflight/post-change check; no repair or deployment.
-- Policy: sql/config/warehouse_policy.json (2026-11-02).
WITH policy AS (
  SELECT * FROM UNNEST([
    STRUCT('115e6258-72f0-468a-9743-731d06a771fa' AS warehouse_id, 'THAILAND' AS country, 'M' AS warehouse_type),
    STRUCT('133983a4-ff7d-4861-805c-0a1bdd51795f', 'THAILAND', 'P'),
    STRUCT('1a21d42d-d648-4fdd-9095-932fceb08a2d', 'VIETNAM', 'NONE'),
    STRUCT('28fc9c4c-6ad6-4dd3-8dda-bc44397c9e0f', 'VIETNAM', 'B'),
    STRUCT('3c86e018-936a-4f33-8dda-7a0ad4f038db', 'VIETNAM', 'B'),
    STRUCT('3fb24787-3208-4fb7-9580-24a3754e51d6', 'VIETNAM', 'P'),
    STRUCT('490ded40-64ba-4424-aaed-399abbf13fbb', 'THAILAND', 'P'),
    STRUCT('4a93fada-d892-4bbd-8547-ec505e6104df', 'VIETNAM', 'P'),
    STRUCT('66184c11-4f37-465b-b5a7-09cb026b9ebd', 'VIETNAM', 'M'),
    STRUCT('76be7836-6dc5-4b1c-9e48-b18e43127453', 'CHINA', 'B'),
    STRUCT('878504e9-fb75-4870-8504-b2ecdbc097ba', 'THAILAND', 'B'),
    STRUCT('ad07f1c9-84be-4c4d-bc5b-4de980ffb97e', 'THAILAND', 'P'),
    STRUCT('c8b7a738-7b1c-4599-ad32-64d145b005c1', 'VIETNAM', 'P'),
    STRUCT('c9aea4ce-e71e-404e-b7c1-8d6ff342d748', 'VIETNAM', 'P'),
    STRUCT('cf854971-c137-4e23-86ec-4bd8fbed6990', 'VIETNAM', 'P'),
    STRUCT('d65e391f-711e-4f9d-81a4-ee54c2d7eca8', 'VIETNAM', 'P'),
    STRUCT('e8d36467-0811-4020-a732-7e6564b5edb4', 'VIETNAM', 'P'),
    STRUCT('eb66793a-2953-44da-8585-da8888111d6d', 'VIETNAM', 'B'),
    STRUCT('f0eb59ac-aa0e-4cf6-971e-01456e5dc3d2', 'THAILAND', 'P')
  ])
), warehouses AS (
  SELECT warehouse_id, country, warehouse_type
  FROM `marine-cycle-484213-b4.core.core_pancake__warehouse`
)
SELECT 'duplicate_id' AS finding, warehouse_id, CAST(COUNT(*) AS STRING) AS detail
FROM warehouses GROUP BY warehouse_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'blank_id', warehouse_id, 'warehouse_id must be nonempty'
FROM warehouses WHERE NULLIF(TRIM(warehouse_id), '') IS NULL
UNION ALL
SELECT 'unmapped_id', w.warehouse_id, 'Review policy; defaults are VIETNAM/P'
FROM warehouses w LEFT JOIN policy p USING (warehouse_id)
WHERE p.warehouse_id IS NULL
UNION ALL
SELECT 'classification_mismatch', w.warehouse_id, CONCAT('Expected ', p.country, '/', p.warehouse_type)
FROM warehouses w JOIN policy p USING (warehouse_id)
WHERE w.country IS DISTINCT FROM p.country OR w.warehouse_type IS DISTINCT FROM p.warehouse_type;
