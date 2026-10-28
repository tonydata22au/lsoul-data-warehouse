CREATE PROCEDURE `marine-cycle-484213-b4`.reportdb.sp_stock_inventory_dashboard_daily(IN p_write_target BOOL)
OPTIONS(
  strict_mode=false)
BEGIN
DECLARE v_full_year_mode BOOL DEFAULT TRUE;
DECLARE v_write_full_target BOOL DEFAULT p_write_target;
DECLARE v_return_details BOOL DEFAULT FALSE;
DECLARE v_run_date DATE DEFAULT CURRENT_DATE('Asia/Ho_Chi_Minh');
DECLARE v_refresh_date DATE DEFAULT DATE_SUB(v_run_date, INTERVAL 1 DAY);

-- Test bounds are used ONLY when full-year mode is FALSE.
DECLARE v_test_from_date DATE DEFAULT DATE '2026-10-05';
DECLARE v_test_to_date DATE DEFAULT DATE '2026-10-13';
DECLARE v_from_date DATE DEFAULT IF(
  v_full_year_mode, DATE_TRUNC(v_refresh_date, YEAR), v_test_from_date);
DECLARE v_to_date DATE DEFAULT IF(
  v_full_year_mode, v_refresh_date, v_test_to_date);

DECLARE v_history_start_date DATE DEFAULT DATE '2025-01-01';
DECLARE v_raw_start_date DATE DEFAULT DATE '2025-01-01';
DECLARE v_order_start_date DATE DEFAULT DATE '2026-01-01';
DECLARE v_raw_batch_end TIMESTAMP DEFAULT TIMESTAMP(DATE_ADD(v_to_date, INTERVAL 2 DAY));

ASSERT p_write_target IS NOT NULL AS 'p_write_target must be TRUE or FALSE';

-- All guards below execute before any source scans.
ASSERT (v_from_date IS NOT NULL AND v_to_date IS NOT NULL AND v_from_date <= v_to_date)
  AS 'Invalid date range';
ASSERT (EXTRACT(YEAR FROM v_from_date) = EXTRACT(YEAR FROM v_run_date)
  AND EXTRACT(YEAR FROM v_to_date) = EXTRACT(YEAR FROM v_run_date))
  AS 'Sales function (0,0) only supports the current-year policy in this script';
ASSERT (NOT v_write_full_target OR v_full_year_mode)
  AS 'Full replacement is blocked in test-range mode';
ASSERT (NOT v_full_year_mode OR (
  v_refresh_date IS NOT NULL
  AND v_refresh_date < v_run_date
  AND EXTRACT(YEAR FROM v_refresh_date) = EXTRACT(YEAR FROM v_run_date)
)) AS 'Full-year mode requires a refresh date in the current year, not in the future';
ASSERT (NOT v_write_full_target OR (
  v_from_date = DATE_TRUNC(v_refresh_date, YEAR) AND v_to_date = v_refresh_date
)) AS 'Full replacement requires the complete selected current-year range';

CREATE TEMP TABLE si_report_dates AS
SELECT report_date AS si_report_date
FROM UNNEST(GENERATE_DATE_ARRAY(v_from_date, v_to_date)) AS report_date;


CREATE TEMP TABLE si_warehouse_scope AS
WITH warehouse_rows AS (
  SELECT DISTINCT
    warehouse_id,
    warehouse_name,
    country,
    warehouse_type
  FROM `marine-cycle-484213-b4.core_pancake.core_warehouse`
), warehouse_dim AS (
  SELECT
    warehouse_id,
    MAX(warehouse_name) AS warehouse_name,
    MAX(country) AS warehouse_country,
    MAX(warehouse_type) AS warehouse_type,
    COUNT(*) AS warehouse_metadata_versions
  FROM warehouse_rows
  GROUP BY
    warehouse_id
), warehouse_scope AS (
  SELECT *
  FROM warehouse_dim
  WHERE (
    warehouse_type NOT IN ('NONE', 'M')
    OR warehouse_type IS NULL
    OR warehouse_id = '1a21d42d-d648-4fdd-9095-932fceb08a2d' -- Hàng lỗi
  )
  AND (
    warehouse_country = 'VIETNAM'
    OR warehouse_id IN (
      '76be7836-6dc5-4b1c-9e48-b18e43127453', -- Backup Trung Quốc
      '878504e9-fb75-4870-8504-b2ecdbc097ba', -- Backup Thái
      'ad07f1c9-84be-4c4d-bc5b-4de980ffb97e'  -- Emsphere
    )
  )
  AND warehouse_id NOT IN (
    'c9aea4ce-e71e-404e-b7c1-8d6ff342d748', -- POP-UP OFFICE
    '28fc9c4c-6ad6-4dd3-8dda-bc44397c9e0f', -- Tổng 480F
    'e8d36467-0811-4020-a732-7e6564b5edb4', -- Whole Sale NT
    'eb66793a-2953-44da-8585-da8888111d6d'  -- LJIN
  )
)
SELECT
  *
FROM warehouse_scope;

CREATE TEMP TABLE si_history_input AS
SELECT h.inserted_at, h.inventory_history_id, h.record_id, h.table_name,
  h.note_type, h.type, h.ref_display_id, h.warehouse_id, h.quantity,
  h.variation_id, h.variation_display_id, h.inv_warehouse_id,
  h.inv_remain_qty, h.inv_actual_remain_qty
FROM `marine-cycle-484213-b4.core_pancake.core_inventory_histories` h
JOIN _SESSION.si_warehouse_scope w ON h.inv_warehouse_id = w.warehouse_id
WHERE h.inserted_at >= DATETIME(v_history_start_date)
  AND h.inserted_at < DATETIME(DATE_ADD(v_to_date, INTERVAL 1 DAY));

CREATE TEMP TABLE si_order_input AS
SELECT _PARTITIONTIME AS observation_partition_at, variation_id, warehouse_id,
  order_id, system_id, _item_id_, updated_at, status_name, cart_quantity,
  quantity_ordered, quantity_returned, quantity_returning
FROM `marine-cycle-484213-b4.raw_pancake.raw_order`
WHERE _PARTITIONTIME >= TIMESTAMP(v_order_start_date)
  AND _PARTITIONTIME < v_raw_batch_end
  AND SAFE.PARSE_DATETIME('%Y%m%d%H%M%S', updated_at)
      < DATETIME(DATE_ADD(v_to_date, INTERVAL 1 DAY));

CREATE TEMP TABLE si_raw_rows AS
WITH raw_rows AS (
  SELECT DISTINCT
    DATE(_PARTITIONTIME) AS batch_date,
    variation_id,
    variation_display_id AS sku,
    variations_warehouses_warehouse_id AS warehouse_id,
    SAFE_CAST(variations_warehouses_remain_quantity AS NUMERIC) AS remain_stock,
    SAFE_CAST(variations_warehouses_actual_remain_quantity AS NUMERIC) AS actual_stock
  FROM `marine-cycle-484213-b4.raw_pancake.raw_product_variations`
  WHERE
    _PARTITIONTIME >= TIMESTAMP(v_raw_start_date)
    AND _PARTITIONTIME < v_raw_batch_end
    AND NOT variation_id IS NULL
    AND TRIM(variation_id) <> ''
)
SELECT
  *
FROM raw_rows;

CREATE TEMP TABLE si_dim_groups AS
WITH dim_rows AS (
  SELECT DISTINCT
    variation_code,
    product_code,
    product_name,
    TRIM(CONCAT(IFNULL(product_name, ''), ' ', IFNULL(product_attributes, ''))) AS variation_attributes,
    category,
    sub_category,
    collection_bst,
    product_launch_date,
    retail_price,
    is_sale_end
  FROM `marine-cycle-484213-b4.reportdb.fn_dim_sku`()
), dim_groups AS (
  SELECT
    variation_code,
    COUNT(*) AS metadata_versions,
    ARRAY_AGG(
      STRUCT(
        product_code,
        product_name,
        variation_attributes,
        category,
        sub_category,
        collection_bst,
        product_launch_date,
        retail_price,
        is_sale_end
      )
      LIMIT 1
    )[OFFSET(0)] AS metadata
  FROM dim_rows
  GROUP BY
    variation_code
)
SELECT
  *
FROM dim_groups;

CREATE TEMP TABLE si_sales_daily AS
WITH sales_daily AS (
  SELECT
    o.period_date,
    o.variation_code,
    o.warehouse_id,
    SUM(o.units_sold) AS units_sold,
    COUNTIF(o.units_sold IS NULL) AS missing_sales_qty_rows
  FROM `marine-cycle-484213-b4.reportdb.fn_order_sku_warehouse_master`(0, 0) AS o
  JOIN _SESSION.si_warehouse_scope AS w
    ON o.warehouse_id = w.warehouse_id
  WHERE
    o.period_date BETWEEN DATE_SUB(v_from_date, INTERVAL 89 DAY) AND v_to_date
  GROUP BY
    o.period_date,
    o.variation_code,
    o.warehouse_id
)
SELECT
  *
FROM sales_daily;

CREATE TEMP TABLE si_source_identity_rows AS
WITH source_history_key_points AS (
  SELECT DISTINCT
    rd.si_report_date AS si_report_date,
    h.variation_id,
    h.variation_display_id AS sku,
    h.inv_warehouse_id AS warehouse_id,
    h.inserted_at
  FROM `_SESSION.si_history_input` AS h
  JOIN _SESSION.si_warehouse_scope AS w
    ON h.inv_warehouse_id = w.warehouse_id
  CROSS JOIN _SESSION.si_report_dates AS rd
  WHERE
    h.inserted_at >= DATETIME(v_history_start_date)
    AND h.inserted_at < DATETIME(DATE_ADD(rd.si_report_date, INTERVAL 1 DAY))
    AND NOT h.variation_id IS NULL
    AND TRIM(h.variation_id) <> ''
  QUALIFY
    DENSE_RANK() OVER (
      PARTITION BY rd.si_report_date, h.variation_id, h.inv_warehouse_id
      ORDER BY h.inserted_at DESC
    ) = 1
), source_identity_rows AS (
  SELECT
    source_history_key_points.si_report_date AS si_report_date,
    variation_id,
    warehouse_id,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(sku))) AS source_sku_versions,
    IF(COUNT(DISTINCT TO_JSON_STRING(STRUCT(sku))) = 1, MAX(sku), NULL) AS sku
  FROM source_history_key_points
  GROUP BY
    variation_id,
    warehouse_id,
    source_history_key_points.si_report_date
)
SELECT
  *
FROM source_identity_rows;

CREATE TEMP TABLE si_latest AS
WITH sku_ids AS (
  SELECT DISTINCT
    source_identity_rows.si_report_date AS si_report_date,
    warehouse_id,
    sku,
    variation_id
  FROM _SESSION.si_source_identity_rows AS source_identity_rows
  WHERE
    NOT sku IS NULL AND NOT LEFT(sku, 2) IN ('TG', 'HT', 'HN', 'HH', 'TD')
), sku_ids_checked AS (
  SELECT
    sku_ids.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date),
    COUNT(DISTINCT sku) OVER (PARTITION BY sku_ids.si_report_date, variation_id, warehouse_id) AS sku_identity_versions
  FROM sku_ids
), raw_order_scope AS (
  SELECT DISTINCT
    k.si_report_date AS si_report_date,
    r.order_id
  FROM `_SESSION.si_order_input` AS r
  JOIN (
    SELECT DISTINCT
      sku_ids.si_report_date AS si_report_date,
      variation_id,
      warehouse_id
    FROM sku_ids
  ) AS k
    ON r.variation_id = k.variation_id AND r.warehouse_id = k.warehouse_id
  WHERE
    r.observation_partition_at >= TIMESTAMP(v_order_start_date)
    AND r.observation_partition_at < TIMESTAMP(DATE_ADD(k.si_report_date, INTERVAL 2 DAY))
    AND SAFE.PARSE_DATETIME('%Y%m%d%H%M%S', r.updated_at) < DATETIME(DATE_ADD(k.si_report_date, INTERVAL 1 DAY))
), order_observations AS (
  SELECT DISTINCT
    k.si_report_date AS si_report_date,
    r.variation_id,
    r.warehouse_id,
    r.order_id,
    r.system_id,
    r._item_id_,
    DATE(r.observation_partition_at) AS batch_date,
    r.updated_at AS updated_raw,
    r.status_name,
    SAFE_CAST(r.cart_quantity AS NUMERIC) AS cart_quantity,
    SAFE_CAST(r.quantity_ordered AS NUMERIC) AS quantity_ordered,
    SAFE_CAST(r.quantity_returned AS NUMERIC) AS quantity_returned,
    SAFE_CAST(r.quantity_returning AS NUMERIC) AS quantity_returning
  FROM `_SESSION.si_order_input` AS r
  JOIN raw_order_scope AS k
    ON r.order_id = k.order_id
  WHERE
    r.observation_partition_at >= TIMESTAMP(v_order_start_date)
    AND r.observation_partition_at < TIMESTAMP(DATE_ADD(k.si_report_date, INTERVAL 2 DAY))
    AND SAFE.PARSE_DATETIME('%Y%m%d%H%M%S', r.updated_at) < DATETIME(DATE_ADD(k.si_report_date, INTERVAL 1 DAY))
), latest_order_payload AS (
  SELECT
    order_observations.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date)
  FROM order_observations
  QUALIFY
    DENSE_RANK() OVER (
      PARTITION BY order_observations.si_report_date, order_id
      ORDER BY batch_date DESC, updated_raw DESC
    ) = 1
), latest AS (
  SELECT DISTINCT
    r.si_report_date AS si_report_date,
    k.sku,
    k.sku_identity_versions,
    r.*
    EXCEPT (si_report_date)
  FROM latest_order_payload AS r
  JOIN sku_ids_checked AS k
    ON (
      r.variation_id = k.variation_id AND r.warehouse_id = k.warehouse_id
    )
    AND k.si_report_date = r.si_report_date
)
SELECT
  *
FROM latest;

CREATE TEMP TABLE si_stock_latest_checked AS
WITH sku_ids AS (
  SELECT DISTINCT
    source_identity_rows.si_report_date AS si_report_date,
    warehouse_id,
    sku,
    variation_id
  FROM _SESSION.si_source_identity_rows AS source_identity_rows
  WHERE
    NOT sku IS NULL AND NOT LEFT(sku, 2) IN ('TG', 'HT', 'HN', 'HH', 'TD')
), stock_latest AS (
  SELECT DISTINCT
    k.si_report_date AS si_report_date,
    k.sku,
    k.warehouse_id,
    h.variation_id,
    h.inserted_at,
    h.inventory_history_id,
    h.table_name,
    h.note_type,
    h.quantity,
    h.record_id,
    h.ref_display_id AS order_ref,
    h.type AS history_action,
    h.warehouse_id AS transaction_warehouse_id,
    REGEXP_EXTRACT(h.type, '#([0-9]+)') AS transfer_ref,
    h.inv_remain_qty AS remain_stock,
    h.inv_actual_remain_qty AS actual_stock
  FROM sku_ids AS k
  JOIN `_SESSION.si_history_input` AS h
    ON h.variation_id = k.variation_id AND h.inv_warehouse_id = k.warehouse_id
  WHERE
    h.inserted_at >= DATETIME(v_history_start_date)
    AND h.inserted_at < DATETIME(DATE_ADD(k.si_report_date, INTERVAL 1 DAY))
  QUALIFY
    DENSE_RANK() OVER (
      PARTITION BY k.si_report_date, k.sku, k.warehouse_id, h.variation_id
      ORDER BY h.inserted_at DESC
    ) = 1
), stock_latest_checked AS (
  SELECT
    stock_latest.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date),
    COUNT(*) OVER (
      PARTITION BY stock_latest.si_report_date, sku, warehouse_id, variation_id, inserted_at
    ) AS point_payload_count
  FROM stock_latest
)
SELECT
  *
FROM stock_latest_checked;

CREATE TEMP TABLE si_line_checked AS
WITH samples AS (
  SELECT DISTINCT
    source_identity_rows.si_report_date AS si_report_date,
    sku,
    warehouse_id
  FROM _SESSION.si_source_identity_rows AS source_identity_rows
  WHERE
    NOT sku IS NULL AND NOT LEFT(sku, 2) IN ('TG', 'HT', 'HN', 'HH', 'TD')
), latest_checked AS (
  SELECT
    latest.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date),
    COUNT(*) OVER (
      PARTITION BY latest.si_report_date, sku, variation_id, warehouse_id, order_id, _item_id_
    ) AS latest_payload_versions,
    COUNT(DISTINCT _item_id_) OVER (PARTITION BY latest.si_report_date, sku, variation_id, warehouse_id, order_id) AS sku_item_count_in_order
  FROM _SESSION.si_latest AS latest
), open_lines AS (
  SELECT
    l.si_report_date AS si_report_date,
    l.*
    EXCEPT (si_report_date)
  FROM latest_checked AS l
  JOIN samples AS s
    ON (
      l.sku = s.sku AND l.warehouse_id = s.warehouse_id
    )
    AND s.si_report_date = l.si_report_date
  WHERE
    status_name IN ('new', 'submitted', 'pending', 'packing', 'returning')
    OR latest_payload_versions > 1
    OR _item_id_ IS NULL
    OR TRIM(_item_id_) = ''
), order_refs AS (
  SELECT DISTINCT
    open_lines.si_report_date AS si_report_date,
    sku,
    warehouse_id,
    variation_id,
    order_id,
    ref
  FROM open_lines
  CROSS JOIN UNNEST([order_id, system_id]) AS ref
  WHERE
    NOT ref IS NULL AND TRIM(ref) <> ''
), matched_events AS (
  SELECT DISTINCT
    r.si_report_date AS si_report_date,
    r.sku,
    r.warehouse_id,
    r.variation_id,
    r.order_id,
    h.inventory_history_id,
    h.record_id,
    h.ref_display_id,
    h.inserted_at,
    h.note_type,
    h.type AS history_action,
    h.quantity
  FROM order_refs AS r
  JOIN `_SESSION.si_history_input` AS h
    ON h.variation_id = r.variation_id
    AND h.inv_warehouse_id = r.warehouse_id
    AND h.warehouse_id = r.warehouse_id
    AND h.ref_display_id = r.ref
  WHERE
    h.inserted_at >= DATETIME(v_history_start_date)
    AND h.inserted_at < DATETIME(DATE_ADD(r.si_report_date, INTERVAL 1 DAY))
    AND h.table_name = 'orders'
), event_checks AS (
  SELECT
    matched_events.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date),
    COUNT(*) OVER (
      PARTITION BY matched_events.si_report_date, sku, warehouse_id, variation_id, order_id, inventory_history_id
    ) AS event_payload_versions
  FROM matched_events
), history_summary AS (
  SELECT
    event_checks.si_report_date AS si_report_date,
    sku,
    warehouse_id,
    variation_id,
    order_id,
    COUNT(*) AS observed_event_payload_count,
    COUNT(DISTINCT record_id) AS history_record_count,
    COUNTIF(event_payload_versions > 1 OR inventory_history_id IS NULL) AS conflicting_event_payload_count,
    COUNTIF(note_type = 6) AS add_event_count,
    COUNTIF(note_type = 11) AS remove_event_count,
    COUNTIF(note_type = 18) AS return_event_count,
    COUNTIF(
      note_type IS NULL
      OR NOT note_type IN (6, 7, 10, 11, 18)
      OR (
        note_type = 7
        AND NOT STARTS_WITH(IFNULL(history_action, ''), 'Thay đổi số lượng trong đơn hàng')
      )
      OR (
        note_type = 10 AND IFNULL(history_action, '') <> 'Nhập kho'
      )
      OR (
        note_type = 18
        AND NOT STARTS_WITH(IFNULL(history_action, ''), 'Trả hàng hàng loạt #')
      )
    ) AS other_note_count,
    COUNTIF(note_type IN (6, 7, 10, 11, 18) AND quantity IS NULL) AS missing_movement_qty_count,
    COUNTIF(
      (
        note_type = 6 AND quantity > 0
      )
      OR (
        note_type = 11 AND quantity < 0
      )
      OR (
        note_type = 18 AND quantity <= 0
      )
    ) AS unexpected_movement_sign_count,
    MIN(inserted_at) AS first_history_at,
    MAX(inserted_at) AS last_history_at,
    IF(
      COUNTIF(event_payload_versions > 1 OR inventory_history_id IS NULL) = 0
      AND COUNTIF(note_type IN (6, 7, 10, 11, 18) AND quantity IS NULL) = 0
      AND COUNTIF(note_type IN (6, 7, 10, 11, 18)) > 0,
      SUM(IF(note_type IN (6, 7, 10, 11, 18), quantity, NULL)),
      NULL
    ) AS history_order_movement_net
  FROM event_checks
  GROUP BY
    sku,
    warehouse_id,
    variation_id,
    order_id,
    event_checks.si_report_date
), line_evidence AS (
  SELECT
    l.si_report_date AS si_report_date,
    l.*
    EXCEPT (si_report_date),
    h.observed_event_payload_count,
    h.history_record_count,
    h.conflicting_event_payload_count,
    h.add_event_count,
    h.remove_event_count,
    h.return_event_count,
    h.other_note_count,
    h.missing_movement_qty_count,
    h.unexpected_movement_sign_count,
    h.first_history_at,
    h.last_history_at,
    h.history_order_movement_net,
    CASE
      WHEN l._item_id_ IS NULL OR TRIM(l._item_id_) = ''
      THEN 'missing_item_id'
      WHEN l.sku_identity_versions <> 1
      OR l.latest_payload_versions <> 1
      OR l.sku_item_count_in_order <> 1
      THEN 'ambiguous_item_mapping'
      WHEN l.status_name = 'returning'
      AND l.quantity_ordered > 0
      AND l.quantity_returned = l.quantity_ordered
      AND l.quantity_returning >= 0
      AND l.quantity_returning <= l.quantity_ordered
      THEN 'full_return_line_not_unshipped_commitment'
      WHEN h.observed_event_payload_count IS NULL
      THEN 'missing_history'
      WHEN h.conflicting_event_payload_count > 0
      OR h.missing_movement_qty_count > 0
      OR h.unexpected_movement_sign_count > 0
      OR h.history_record_count <> 1
      THEN 'unsafe_history'
      WHEN h.other_note_count > 0
      THEN 'other_history_notes_need_review'
      WHEN h.return_event_count > 0
      AND (
        h.add_event_count = 0
        OR h.history_order_movement_net IS NULL
        OR h.history_order_movement_net <> 0
      )
      THEN 'unbalanced_return_movements_need_review'
      WHEN h.add_event_count > 0 AND h.history_order_movement_net = 0
      THEN 'explicit_order_movements_balanced'
      WHEN l.status_name = 'returning'
      THEN 'returning_not_added_to_candidate'
      WHEN l.status_name IN ('new', 'submitted', 'pending', 'packing')
      AND l.cart_quantity > 0
      AND h.add_event_count > 0
      AND h.history_order_movement_net = -l.cart_quantity
      THEN 'unshipped_commitment_supported'
      WHEN l.status_name IN ('new', 'submitted', 'pending', 'packing')
      AND l.cart_quantity = 0
      AND l.quantity_ordered > 0
      AND l.quantity_returned = 0
      AND l.quantity_returning = 0
      AND h.add_event_count > 0
      AND h.history_order_movement_net < 0
      AND -h.history_order_movement_net = l.quantity_ordered
      THEN 'cart_zero_history_reservation_trial'
      ELSE 'unresolved_line'
    END AS evidence_result
  FROM open_lines AS l
  LEFT JOIN history_summary AS h
    ON (
      l.sku = h.sku
      AND l.warehouse_id = h.warehouse_id
      AND l.variation_id = h.variation_id
      AND l.order_id = h.order_id
    )
    AND h.si_report_date = l.si_report_date
), line_candidate AS (
  SELECT
    line_evidence.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date),
    CASE
      WHEN evidence_result = 'unshipped_commitment_supported'
      THEN cart_quantity
      WHEN evidence_result = 'cart_zero_history_reservation_trial'
      THEN -history_order_movement_net
      WHEN evidence_result IN (
        'explicit_order_movements_balanced',
        'returning_not_added_to_candidate',
        'full_return_line_not_unshipped_commitment'
      )
      THEN CAST(0 AS NUMERIC)
      ELSE CAST(NULL AS NUMERIC)
    END AS candidate_commitment_qty
  FROM line_evidence
), core_item_flags AS (
  SELECT
    l.si_report_date AS si_report_date,
    l.sku,
    l.warehouse_id,
    l.variation_id,
    l.order_id,
    l._item_id_,
    COUNTIF(
      SAFE.PARSE_DATETIME('%Y%m%d%H%M%S', i.updated_at) >= DATETIME(DATE_ADD(l.si_report_date, INTERVAL 1 DAY))
    ) > 0 AS core_item_updated_after_snapshot
  FROM line_candidate AS l
  JOIN `marine-cycle-484213-b4.core_pancake.core_order_item` AS i
    ON l._item_id_ = i.order_item_id
    AND l.order_id = i.order_id
    AND l.variation_id = i.variation_id
  GROUP BY
    l.sku,
    l.warehouse_id,
    l.variation_id,
    l.order_id,
    l._item_id_,
    l.si_report_date
), line_checked AS (
  SELECT
    l.si_report_date AS si_report_date,
    l.*
    EXCEPT (si_report_date),
    f.core_item_updated_after_snapshot
  FROM line_candidate AS l
  LEFT JOIN core_item_flags AS f
    ON (
      l.sku = f.sku
      AND l.warehouse_id = f.warehouse_id
      AND l.variation_id = f.variation_id
      AND l.order_id = f.order_id
      AND l._item_id_ = f._item_id_
    )
    AND f.si_report_date = l.si_report_date
)
SELECT
  *
FROM line_checked;

CREATE TEMP TABLE si_existing_review AS
WITH samples AS (
  SELECT DISTINCT
    source_identity_rows.si_report_date AS si_report_date,
    sku,
    warehouse_id
  FROM _SESSION.si_source_identity_rows AS source_identity_rows
  WHERE
    NOT sku IS NULL AND NOT LEFT(sku, 2) IN ('TG', 'HT', 'HN', 'HH', 'TD')
), sku_ids AS (
  SELECT DISTINCT
    source_identity_rows.si_report_date AS si_report_date,
    warehouse_id,
    sku,
    variation_id
  FROM _SESSION.si_source_identity_rows AS source_identity_rows
  WHERE
    NOT sku IS NULL AND NOT LEFT(sku, 2) IN ('TG', 'HT', 'HN', 'HH', 'TD')
), stock_latest AS (
  SELECT DISTINCT
    k.si_report_date AS si_report_date,
    k.sku,
    k.warehouse_id,
    h.variation_id,
    h.inserted_at,
    h.inventory_history_id,
    h.table_name,
    h.note_type,
    h.quantity,
    h.record_id,
    h.ref_display_id AS order_ref,
    h.type AS history_action,
    h.warehouse_id AS transaction_warehouse_id,
    REGEXP_EXTRACT(h.type, '#([0-9]+)') AS transfer_ref,
    h.inv_remain_qty AS remain_stock,
    h.inv_actual_remain_qty AS actual_stock
  FROM sku_ids AS k
  JOIN `_SESSION.si_history_input` AS h
    ON h.variation_id = k.variation_id AND h.inv_warehouse_id = k.warehouse_id
  WHERE
    h.inserted_at >= DATETIME(v_history_start_date)
    AND h.inserted_at < DATETIME(DATE_ADD(k.si_report_date, INTERVAL 1 DAY))
  QUALIFY
    DENSE_RANK() OVER (
      PARTITION BY k.si_report_date, k.sku, k.warehouse_id, h.variation_id
      ORDER BY h.inserted_at DESC
    ) = 1
), stock_transfer_candidates AS (
  SELECT
    p.si_report_date AS si_report_date,
    c.sku,
    c.warehouse_id,
    c.variation_id,
    c.inserted_at,
    c.inventory_history_id AS terminal_id
  FROM _SESSION.si_stock_latest_checked AS p
  JOIN _SESSION.si_stock_latest_checked AS c
    ON (
      p.sku = c.sku
      AND p.warehouse_id = c.warehouse_id
      AND p.variation_id = c.variation_id
      AND p.inserted_at = c.inserted_at
      AND p.record_id = c.record_id
      AND p.transfer_ref = c.transfer_ref
    )
    AND c.si_report_date = p.si_report_date
  WHERE
    p.point_payload_count = 2
    AND c.point_payload_count = 2
    AND p.table_name = 'warehouse_transfers'
    AND c.table_name = 'warehouse_transfers'
    AND p.note_type = 19
    AND c.note_type = 23
    AND NOT p.record_id IS NULL
    AND TRIM(p.record_id) <> ''
    AND NOT p.transfer_ref IS NULL
    AND NOT p.inventory_history_id IS NULL
    AND NOT c.inventory_history_id IS NULL
    AND p.inventory_history_id <> c.inventory_history_id
    AND p.transaction_warehouse_id <> c.transaction_warehouse_id
    AND c.quantity > 0
    AND p.quantity = -c.quantity
    AND (
      (
        c.transaction_warehouse_id = c.warehouse_id
        AND p.transaction_warehouse_id <> p.warehouse_id
        AND c.remain_stock = p.remain_stock + c.quantity
        AND c.actual_stock = p.actual_stock + c.quantity
      )
      OR (
        p.transaction_warehouse_id = p.warehouse_id
        AND c.transaction_warehouse_id <> c.warehouse_id
        AND c.remain_stock = p.remain_stock
        AND c.actual_stock = p.actual_stock - c.quantity
      )
    )
), stock_order_candidates AS (
  SELECT
    p.si_report_date AS si_report_date,
    c.sku,
    c.warehouse_id,
    c.variation_id,
    c.inserted_at,
    c.inventory_history_id AS terminal_id
  FROM _SESSION.si_stock_latest_checked AS p
  JOIN _SESSION.si_stock_latest_checked AS c
    ON (
      p.sku = c.sku
      AND p.warehouse_id = c.warehouse_id
      AND p.variation_id = c.variation_id
      AND p.inserted_at = c.inserted_at
    )
    AND c.si_report_date = p.si_report_date
  WHERE
    p.point_payload_count = 2
    AND c.point_payload_count = 2
    AND p.table_name = 'orders'
    AND c.table_name = 'orders'
    AND NOT p.inventory_history_id IS NULL
    AND NOT c.inventory_history_id IS NULL
    AND p.inventory_history_id <> c.inventory_history_id
    AND p.transaction_warehouse_id = p.warehouse_id
    AND c.transaction_warehouse_id = c.warehouse_id
    AND NOT p.record_id IS NULL
    AND TRIM(p.record_id) <> ''
    AND NOT c.record_id IS NULL
    AND TRIM(c.record_id) <> ''
    AND NOT p.order_ref IS NULL
    AND TRIM(p.order_ref) <> ''
    AND NOT c.order_ref IS NULL
    AND TRIM(c.order_ref) <> ''
    AND p.actual_stock = c.actual_stock
    AND p.note_type = 6
    AND p.quantity < 0
    AND c.remain_stock = p.remain_stock + c.quantity
    AND (
      (
        c.note_type = 10
        AND c.history_action = 'Nhập kho'
        AND c.record_id = p.record_id
        AND c.order_ref = p.order_ref
        AND c.quantity > 0
        AND p.quantity = -c.quantity
      )
      OR (
        c.note_type = 6
        AND c.quantity < 0
        AND c.record_id <> p.record_id
        AND c.order_ref <> p.order_ref
      )
    )
), stock_terminal_candidates AS (
  SELECT
    stock_transfer_candidates.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date)
  FROM stock_transfer_candidates
  UNION ALL
  SELECT
    stock_order_candidates.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date)
  FROM stock_order_candidates
), stock_terminal_unique AS (
  SELECT
    stock_terminal_candidates.si_report_date AS si_report_date,
    sku,
    warehouse_id,
    variation_id,
    inserted_at,
    IF(COUNT(*) = 1, MAX(terminal_id), NULL) AS terminal_id
  FROM stock_terminal_candidates
  GROUP BY
    sku,
    warehouse_id,
    variation_id,
    inserted_at,
    stock_terminal_candidates.si_report_date
), stock_resolved AS (
  SELECT
    h.si_report_date AS si_report_date,
    h.*
    EXCEPT (si_report_date)
  FROM stock_latest AS h
  LEFT JOIN stock_terminal_unique AS t
    ON (
      h.sku = t.sku
      AND h.warehouse_id = t.warehouse_id
      AND h.variation_id = t.variation_id
      AND h.inserted_at = t.inserted_at
    )
    AND t.si_report_date = h.si_report_date
  WHERE
    t.terminal_id IS NULL OR h.inventory_history_id = t.terminal_id
), stock_summary AS (
  SELECT
    stock_resolved.si_report_date AS si_report_date,
    sku,
    warehouse_id,
    MAX(inserted_at) AS stock_history_at,
    COUNT(DISTINCT variation_id) AS variation_id_count,
    COUNT(DISTINCT remain_stock) AS remain_versions,
    COUNT(DISTINCT actual_stock) AS actual_versions,
    IF(
      COUNT(DISTINCT variation_id) = 1
      AND COUNT(DISTINCT remain_stock) = 1
      AND COUNTIF(remain_stock IS NULL) = 0,
      MAX(remain_stock),
      NULL
    ) AS remain_stock,
    IF(
      COUNT(DISTINCT variation_id) = 1
      AND COUNT(DISTINCT actual_stock) = 1
      AND COUNTIF(actual_stock IS NULL) = 0,
      MAX(actual_stock),
      NULL
    ) AS actual_stock
  FROM stock_resolved
  GROUP BY
    sku,
    warehouse_id,
    stock_resolved.si_report_date
), raw_coverage AS (
  SELECT
    l.si_report_date AS si_report_date,
    l.sku,
    l.warehouse_id,
    COUNT(*) AS observed_latest_line_count
  FROM _SESSION.si_latest AS l
  JOIN samples AS s
    ON (
      l.sku = s.sku AND l.warehouse_id = s.warehouse_id
    )
    AND s.si_report_date = l.si_report_date
  GROUP BY
    l.sku,
    l.warehouse_id,
    l.si_report_date
), commitment_summary AS (
  SELECT
    line_checked.si_report_date AS si_report_date,
    sku,
    warehouse_id,
    COUNT(*) AS inspected_open_line_count,
    COUNTIF(candidate_commitment_qty IS NULL) AS unresolved_open_line_count,
    COUNTIF(evidence_result = 'explicit_order_movements_balanced') AS balanced_order_movement_line_count,
    COUNTIF(status_name = 'returning') AS returning_line_count,
    COUNTIF(core_item_updated_after_snapshot) AS open_lines_with_post_cutoff_core_update,
    COUNTIF(candidate_commitment_qty > 0 AND batch_date < line_checked.si_report_date) AS commitments_with_old_observation,
    IF(COUNTIF(candidate_commitment_qty IS NULL) = 0, SUM(candidate_commitment_qty), NULL) AS candidate_commitment_qty
  FROM _SESSION.si_line_checked AS line_checked
  GROUP BY
    sku,
    warehouse_id,
    line_checked.si_report_date
), trial AS (
  SELECT
    s.si_report_date AS si_report_date,
    s.sku,
    s.warehouse_id,
    st.stock_history_at,
    st.variation_id_count,
    st.remain_versions,
    st.actual_versions,
    st.remain_stock,
    st.actual_stock,
    r.observed_latest_line_count,
    c.inspected_open_line_count,
    c.unresolved_open_line_count,
    c.balanced_order_movement_line_count,
    c.returning_line_count,
    c.open_lines_with_post_cutoff_core_update,
    c.commitments_with_old_observation,
    CASE
      WHEN r.observed_latest_line_count IS NULL
      THEN NULL
      WHEN c.inspected_open_line_count IS NULL
      THEN CAST(0 AS NUMERIC)
      ELSE c.candidate_commitment_qty
    END AS candidate_commitment_qty
  FROM samples AS s
  LEFT JOIN stock_summary AS st
    ON (
      s.sku = st.sku AND s.warehouse_id = st.warehouse_id
    )
    AND st.si_report_date = s.si_report_date
  LEFT JOIN raw_coverage AS r
    ON (
      s.sku = r.sku AND s.warehouse_id = r.warehouse_id
    )
    AND r.si_report_date = s.si_report_date
  LEFT JOIN commitment_summary AS c
    ON (
      s.sku = c.sku AND s.warehouse_id = c.warehouse_id
    )
    AND c.si_report_date = s.si_report_date
), existing_review AS (
  SELECT
    trial.si_report_date AS si_report_date,
    trial.si_report_date AS snapshot_date,
    sku,
    warehouse_id,
    stock_history_at,
    variation_id_count,
    remain_versions,
    actual_versions,
    remain_stock,
    actual_stock,
    observed_latest_line_count,
    inspected_open_line_count,
    unresolved_open_line_count,
    balanced_order_movement_line_count,
    returning_line_count,
    open_lines_with_post_cutoff_core_update,
    commitments_with_old_observation,
    candidate_commitment_qty,
    CASE
      WHEN NOT candidate_commitment_qty IS NULL
      THEN remain_stock + candidate_commitment_qty
      WHEN observed_latest_line_count IS NULL AND remain_stock = actual_stock
      THEN remain_stock
      ELSE NULL
    END AS trial_stock,
    CASE
      WHEN NOT candidate_commitment_qty IS NULL
      THEN 'remain_plus_observed_commitments'
      WHEN observed_latest_line_count IS NULL AND remain_stock = actual_stock
      THEN 'source_snapshot_consensus_without_order_observation'
      ELSE 'unresolved'
    END AS stock_candidate_source,
    CASE
      WHEN remain_stock IS NULL
      THEN 'missing_or_conflicting_history_stock'
      WHEN observed_latest_line_count IS NULL AND remain_stock = actual_stock
      THEN 'numeric_source_snapshot_consensus_without_order_observation'
      WHEN candidate_commitment_qty IS NULL
      THEN 'missing_or_unresolved_order_evidence'
      WHEN open_lines_with_post_cutoff_core_update > 0
      THEN 'numeric_trial_with_post_cutoff_core_update'
      WHEN returning_line_count > 0
      THEN 'numeric_trial_with_returning_lines'
      WHEN commitments_with_old_observation > 0
      THEN 'numeric_trial_with_old_commitment_observation'
      ELSE 'numeric_trial_coverage_not_verified'
    END AS review_status
  FROM trial
)
SELECT
  *
FROM existing_review;

CREATE TEMP TABLE si_latest_batch AS
WITH latest_batch AS (
  SELECT
    rd.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date)
  FROM _SESSION.si_raw_rows AS raw_rows
  CROSS JOIN _SESSION.si_report_dates AS rd
  WHERE
    batch_date <= DATE_ADD(rd.si_report_date, INTERVAL 1 DAY)
  QUALIFY
    batch_date = MAX(batch_date) OVER (PARTITION BY rd.si_report_date, variation_id)
)
SELECT
  *
FROM latest_batch;

CREATE TEMP TABLE si_raw_before_cutoff_latest AS
WITH raw_before_cutoff_latest AS (
  SELECT
    rd.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date)
  FROM _SESSION.si_raw_rows AS raw_rows
  CROSS JOIN _SESSION.si_report_dates AS rd
  WHERE
    batch_date <= rd.si_report_date
  QUALIFY
    batch_date = MAX(batch_date) OVER (PARTITION BY rd.si_report_date, variation_id)
)
SELECT
  *
FROM raw_before_cutoff_latest;

CREATE TEMP TABLE si_additional_source_rows AS
WITH samples AS (
  SELECT DISTINCT
    source_identity_rows.si_report_date AS si_report_date,
    sku,
    warehouse_id
  FROM _SESSION.si_source_identity_rows AS source_identity_rows
  WHERE
    NOT sku IS NULL AND NOT LEFT(sku, 2) IN ('TG', 'HT', 'HN', 'HH', 'TD')
), identity_check AS (
  SELECT
    latest_batch.si_report_date AS si_report_date,
    variation_id,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(sku))) AS sku_versions,
    IF(COUNT(DISTINCT TO_JSON_STRING(STRUCT(sku))) = 1, MAX(sku), NULL) AS canonical_sku
  FROM _SESSION.si_latest_batch AS latest_batch
  GROUP BY
    variation_id,
    latest_batch.si_report_date
), raw_stock AS (
  SELECT
    r.si_report_date AS si_report_date,
    i.canonical_sku AS sku,
    r.variation_id,
    r.warehouse_id,
    MAX(r.batch_date) AS stock_observation_batch,
    i.sku_versions,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(r.remain_stock))) AS remain_versions,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(r.actual_stock))) AS actual_versions,
    IF(
      COUNT(DISTINCT TO_JSON_STRING(STRUCT(r.remain_stock))) = 1,
      MAX(r.remain_stock),
      NULL
    ) AS remain_stock,
    IF(
      COUNT(DISTINCT TO_JSON_STRING(STRUCT(r.actual_stock))) = 1,
      MAX(r.actual_stock),
      NULL
    ) AS actual_stock,
    COUNTIF(r.remain_stock > 0 OR r.actual_stock > 0) > 0 AS has_positive_payload
  FROM _SESSION.si_latest_batch AS r
  JOIN identity_check AS i
    ON r.variation_id = i.variation_id AND i.si_report_date = r.si_report_date
  JOIN _SESSION.si_warehouse_scope AS w
    ON r.warehouse_id = w.warehouse_id
  GROUP BY
    i.canonical_sku,
    r.variation_id,
    r.warehouse_id,
    i.sku_versions,
    r.si_report_date
), checked AS (
  SELECT
    raw_stock.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date),
    COUNT(DISTINCT variation_id) OVER (PARTITION BY raw_stock.si_report_date, warehouse_id, sku) AS variation_ids_for_sku
  FROM raw_stock
), dashboard_keys AS (
  SELECT
    samples.si_report_date AS si_report_date,
    sku,
    warehouse_id
  FROM samples
), additional_source_rows AS (
  SELECT
    r.si_report_date AS si_report_date,
    r.sku,
    r.variation_id,
    r.warehouse_id,
    r.stock_observation_batch,
    DATE_DIFF(r.si_report_date, r.stock_observation_batch, DAY) AS observation_age_days,
    r.stock_observation_batch > r.si_report_date AS observed_after_snapshot_day,
    r.sku_versions,
    r.variation_ids_for_sku,
    r.remain_versions,
    r.actual_versions,
    r.remain_stock,
    r.actual_stock,
    CASE
      WHEN r.sku IS NULL OR r.sku_versions <> 1 OR r.variation_ids_for_sku <> 1
      THEN 'identity_needs_review'
      WHEN r.remain_stock IS NULL OR r.actual_stock IS NULL
      THEN 'stock_missing_or_conflicting'
      WHEN r.remain_stock = r.actual_stock
      THEN 'raw_stock_consensus'
      ELSE 'raw_stock_fields_differ'
    END AS review_status
  FROM checked AS r
  LEFT JOIN dashboard_keys AS d
    ON (
      r.sku = d.sku AND r.warehouse_id = d.warehouse_id
    )
    AND d.si_report_date = r.si_report_date
  WHERE
    d.sku IS NULL
    AND (
      r.sku IS NULL OR NOT LEFT(r.sku, 2) IN ('TG', 'HT', 'HN', 'HH', 'TD')
    )
)
SELECT
  *
FROM additional_source_rows;

CREATE TEMP TABLE si_raw_existing_identity_checked AS
WITH raw_before_cutoff_identity AS (
  SELECT
    raw_before_cutoff_latest.si_report_date AS si_report_date,
    variation_id,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(sku))) AS sku_versions,
    MAX(sku) AS canonical_sku
  FROM _SESSION.si_raw_before_cutoff_latest AS raw_before_cutoff_latest
  GROUP BY
    variation_id,
    raw_before_cutoff_latest.si_report_date
), raw_existing_candidates AS (
  SELECT
    e.si_report_date AS si_report_date,
    e.sku,
    e.warehouse_id,
    r.variation_id,
    MAX(r.batch_date) AS raw_candidate_batch,
    MAX(i.sku_versions) AS raw_identity_versions,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(r.remain_stock))) AS raw_remain_versions,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(r.actual_stock))) AS raw_actual_versions,
    MAX(r.remain_stock) AS raw_candidate_remain,
    MAX(r.actual_stock) AS raw_candidate_actual
  FROM _SESSION.si_existing_review AS e
  JOIN raw_before_cutoff_identity AS i
    ON e.sku = i.canonical_sku AND i.si_report_date = e.si_report_date
  JOIN _SESSION.si_raw_before_cutoff_latest AS r
    ON (
      i.variation_id = r.variation_id AND e.warehouse_id = r.warehouse_id
    )
    AND r.si_report_date = e.si_report_date
  GROUP BY
    e.sku,
    e.warehouse_id,
    r.variation_id,
    e.si_report_date
), raw_existing_identity_checked AS (
  SELECT
    raw_existing_candidates.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date),
    COUNT(*) OVER (PARTITION BY raw_existing_candidates.si_report_date, sku, warehouse_id) AS raw_ids_for_key
  FROM raw_existing_candidates
)
SELECT
  *
FROM raw_existing_identity_checked;

CREATE TEMP TABLE si_dashboard_result AS
WITH sku_ids AS (
  SELECT DISTINCT
    source_identity_rows.si_report_date AS si_report_date,
    warehouse_id,
    sku,
    variation_id
  FROM _SESSION.si_source_identity_rows AS source_identity_rows
  WHERE
    NOT sku IS NULL AND NOT LEFT(sku, 2) IN ('TG', 'HT', 'HN', 'HH', 'TD')
), additional_history_check AS (
  SELECT
    r.si_report_date AS si_report_date,
    r.variation_id,
    r.warehouse_id,
    COUNTIF(NOT h.inserted_at IS NULL) AS history_rows_at_or_after_observation,
    MAX(h.inserted_at) AS latest_history_at_or_after_observation
  FROM _SESSION.si_additional_source_rows AS r
  LEFT JOIN _SESSION.si_history_input AS h
    ON h.variation_id = r.variation_id
    AND h.inv_warehouse_id = r.warehouse_id
    AND h.inserted_at >= DATETIME(v_history_start_date)
    AND h.inserted_at < DATETIME(DATE_ADD(r.si_report_date, INTERVAL '1' DAY))
    AND DATE(h.inserted_at) >= r.stock_observation_batch
  GROUP BY
    r.variation_id,
    r.warehouse_id,
    r.si_report_date
), additional_review AS (
  SELECT
    r.si_report_date AS si_report_date,
    r.*
    EXCEPT (si_report_date),
    h.history_rows_at_or_after_observation,
    h.latest_history_at_or_after_observation,
    CASE
      WHEN r.review_status <> 'raw_stock_consensus'
      THEN NULL
      WHEN r.observed_after_snapshot_day
      THEN NULL
      WHEN h.history_rows_at_or_after_observation IS NULL
      OR h.history_rows_at_or_after_observation > 0
      THEN NULL
      ELSE r.remain_stock
    END AS trial_stock,
    CASE
      WHEN r.review_status <> 'raw_stock_consensus'
      THEN r.review_status
      WHEN r.observed_after_snapshot_day
      THEN 'raw_observation_after_snapshot_day'
      WHEN h.history_rows_at_or_after_observation IS NULL
      OR h.history_rows_at_or_after_observation > 0
      THEN 'later_or_same_day_history_needs_review'
      ELSE 'numeric_raw_snapshot_consensus_no_later_history_observed'
    END AS coverage_review_status
  FROM _SESSION.si_additional_source_rows AS r
  LEFT JOIN additional_history_check AS h
    ON (
      r.variation_id = h.variation_id AND r.warehouse_id = h.warehouse_id
    )
    AND h.si_report_date = r.si_report_date
), raw_existing_history_guard AS (
  SELECT
    r.si_report_date AS si_report_date,
    r.sku,
    r.warehouse_id,
    r.variation_id,
    COUNTIF(NOT h.inserted_at IS NULL) AS history_rows_since_raw_day
  FROM _SESSION.si_raw_existing_identity_checked AS r
  LEFT JOIN _SESSION.si_history_input AS h
    ON r.variation_id = h.variation_id
    AND r.warehouse_id = h.inv_warehouse_id
    AND h.inserted_at >= DATETIME(v_history_start_date)
    AND h.inserted_at < DATETIME(DATE_ADD(r.si_report_date, INTERVAL '1' DAY))
    AND DATE(h.inserted_at) >= r.raw_candidate_batch
  GROUP BY
    r.sku,
    r.warehouse_id,
    r.variation_id,
    r.si_report_date
), raw_existing_review AS (
  SELECT
    r.si_report_date AS si_report_date,
    r.*
    EXCEPT (si_report_date),
    g.history_rows_since_raw_day,
    CASE
      WHEN r.raw_ids_for_key <> 1 OR r.raw_identity_versions <> 1
      THEN 'raw_identity_conflict'
      WHEN e.variation_id_count <> 1 OR e.variation_id_count IS NULL
      THEN 'history_identity_needs_review'
      WHEN k.variation_id IS NULL
      THEN 'raw_history_id_mismatch'
      WHEN r.raw_remain_versions <> 1
      OR r.raw_actual_versions <> 1
      OR r.raw_candidate_remain IS NULL
      OR r.raw_candidate_actual IS NULL
      THEN 'raw_stock_missing_or_conflicting'
      WHEN r.raw_candidate_remain <> r.raw_candidate_actual
      THEN 'raw_stock_fields_differ'
      WHEN e.stock_history_at IS NULL OR r.raw_candidate_batch <= DATE(e.stock_history_at)
      THEN 'raw_not_strictly_later_than_history'
      WHEN g.history_rows_since_raw_day IS NULL OR g.history_rows_since_raw_day > 0
      THEN 'history_at_or_after_raw_observation'
      ELSE 'eligible_newer_raw_snapshot_trial'
    END AS raw_precedence_status
  FROM _SESSION.si_raw_existing_identity_checked AS r
  JOIN _SESSION.si_existing_review AS e
    ON (
      r.sku = e.sku AND r.warehouse_id = e.warehouse_id
    )
    AND e.si_report_date = r.si_report_date
  LEFT JOIN raw_existing_history_guard AS g
    ON (
      r.sku = g.sku
      AND r.warehouse_id = g.warehouse_id
      AND r.variation_id = g.variation_id
    )
    AND g.si_report_date = r.si_report_date
  LEFT JOIN sku_ids AS k
    ON (
      r.sku = k.sku
      AND r.warehouse_id = k.warehouse_id
      AND r.variation_id = k.variation_id
    )
    AND k.si_report_date = r.si_report_date
), raw_existing_audit AS (
  SELECT
    raw_existing_review.si_report_date AS si_report_date,
    sku,
    warehouse_id,
    COUNTIF(raw_precedence_status = 'eligible_newer_raw_snapshot_trial') AS eligible_raw_snapshot_count,
    MAX(
      IF(
        raw_precedence_status = 'eligible_newer_raw_snapshot_trial',
        raw_candidate_remain,
        NULL
      )
    ) AS newer_raw_trial_stock,
    MAX(
      IF(
        raw_precedence_status = 'eligible_newer_raw_snapshot_trial',
        raw_candidate_batch,
        NULL
      )
    ) AS newer_raw_observation_batch
  FROM raw_existing_review
  GROUP BY
    sku,
    warehouse_id,
    raw_existing_review.si_report_date
), cart_zero_audit AS (
  SELECT
    line_checked.si_report_date AS si_report_date,
    sku,
    warehouse_id,
    COUNT(*) AS cart_zero_history_trial_line_count,
    SUM(candidate_commitment_qty) AS cart_zero_history_trial_qty,
    COUNTIF(batch_date < line_checked.si_report_date) AS cart_zero_trial_old_observation_lines
  FROM _SESSION.si_line_checked AS line_checked
  WHERE
    evidence_result = 'cart_zero_history_reservation_trial'
  GROUP BY
    sku,
    warehouse_id,
    line_checked.si_report_date
), full_return_audit AS (
  SELECT
    line_checked.si_report_date AS si_report_date,
    sku,
    warehouse_id,
    COUNT(*) AS full_return_non_commitment_line_count,
    COUNTIF(observed_event_payload_count IS NULL) AS full_return_missing_history_line_count,
    COUNTIF(
      other_note_count > 0
      OR conflicting_event_payload_count > 0
      OR missing_movement_qty_count > 0
      OR unexpected_movement_sign_count > 0
      OR history_record_count <> 1
    ) AS full_return_history_review_line_count
  FROM _SESSION.si_line_checked AS line_checked
  WHERE
    evidence_result = 'full_return_line_not_unshipped_commitment'
  GROUP BY
    sku,
    warehouse_id,
    line_checked.si_report_date
), orphan_history_audit AS (
  SELECT
    source_identity_rows.si_report_date AS si_report_date,
    warehouse_id,
    COUNT(*) AS unresolved_history_identity_count
  FROM _SESSION.si_source_identity_rows AS source_identity_rows
  WHERE
    sku IS NULL
  GROUP BY
    warehouse_id,
    source_identity_rows.si_report_date
), combined_review AS (
  SELECT
    e.si_report_date AS si_report_date,
    e.snapshot_date,
    e.sku,
    e.warehouse_id,
    'history_source_key' AS row_origin,
    e.stock_history_at,
    CAST(NULL AS DATE) AS raw_observation_batch,
    CAST(NULL AS INT64) AS raw_observation_age_days,
    e.remain_stock,
    e.actual_stock,
    e.candidate_commitment_qty,
    e.trial_stock,
    e.stock_candidate_source,
    e.review_status,
    e.unresolved_open_line_count,
    e.returning_line_count,
    e.open_lines_with_post_cutoff_core_update,
    e.commitments_with_old_observation,
    CAST(NULL AS INT64) AS history_rows_at_or_after_raw_observation,
    CAST(NULL AS STRING) AS raw_variation_id
  FROM _SESSION.si_existing_review AS e
  UNION ALL
  SELECT
    r.si_report_date AS si_report_date,
    r.si_report_date,
    r.sku,
    r.warehouse_id,
    'additional_raw_source_key',
    CAST(NULL AS DATETIME),
    r.stock_observation_batch,
    r.observation_age_days,
    r.remain_stock,
    r.actual_stock,
    CAST(NULL AS NUMERIC),
    r.trial_stock,
    'raw_variation_snapshot',
    r.coverage_review_status,
    CAST(NULL AS INT64),
    CAST(NULL AS INT64),
    CAST(NULL AS INT64),
    CAST(NULL AS INT64),
    r.history_rows_at_or_after_observation,
    r.variation_id AS raw_variation_id
  FROM additional_review AS r
), stock_result AS (
  SELECT
    r.si_report_date AS si_report_date,
    r.*
    EXCEPT (trial_stock, stock_candidate_source, review_status, si_report_date),
    IF(b.eligible_raw_snapshot_count = 1, b.newer_raw_trial_stock, r.trial_stock) AS trial_stock,
    IF(
      b.eligible_raw_snapshot_count = 1,
      'newer_raw_snapshot_consensus_trial',
      r.stock_candidate_source
    ) AS stock_candidate_source,
    CASE
      WHEN b.eligible_raw_snapshot_count = 1
      THEN 'numeric_newer_raw_snapshot_trial'
      WHEN z.cart_zero_history_trial_line_count > 0 AND NOT r.trial_stock IS NULL
      THEN 'numeric_cart_zero_history_reservation_trial'
      ELSE r.review_status
    END AS review_status,
    IFNULL(b.eligible_raw_snapshot_count = 1, FALSE) AS newer_raw_snapshot_applied,
    b.newer_raw_observation_batch,
    z.cart_zero_history_trial_line_count,
    z.cart_zero_history_trial_qty,
    z.cart_zero_trial_old_observation_lines,
    a.full_return_non_commitment_line_count,
    a.full_return_missing_history_line_count,
    a.full_return_history_review_line_count
  FROM combined_review AS r
  LEFT JOIN full_return_audit AS a
    ON (
      r.sku = a.sku AND r.warehouse_id = a.warehouse_id
    )
    AND a.si_report_date = r.si_report_date
  LEFT JOIN cart_zero_audit AS z
    ON (
      r.sku = z.sku AND r.warehouse_id = z.warehouse_id
    )
    AND z.si_report_date = r.si_report_date
  LEFT JOIN raw_existing_audit AS b
    ON (
      r.sku = b.sku AND r.warehouse_id = b.warehouse_id
    )
    AND b.si_report_date = r.si_report_date
), sales_windows AS (
  SELECT
    rd.si_report_date AS si_report_date,
    variation_code,
    warehouse_id,
    COUNT(*) AS observed_sales_day_count,
    SUM(missing_sales_qty_rows) AS missing_sales_qty_rows,
    IF(
      COUNTIF(
        period_date >= DATE_SUB(rd.si_report_date, INTERVAL '6' DAY)
        AND missing_sales_qty_rows > 0
      ) = 0,
      SUM(IF(period_date >= DATE_SUB(rd.si_report_date, INTERVAL '6' DAY), units_sold, 0)),
      NULL
    ) AS units_sold_7d,
    IF(SUM(missing_sales_qty_rows) = 0, SUM(units_sold), NULL) AS units_sold_90d,
    IF(
      COUNTIF(
        period_date >= DATE_TRUNC(rd.si_report_date, MONTH)
        AND missing_sales_qty_rows > 0
      ) = 0,
      SUM(IF(period_date >= DATE_TRUNC(rd.si_report_date, MONTH), units_sold, 0)),
      NULL
    ) AS units_sold_mtd
  FROM _SESSION.si_sales_daily AS sales_daily
  CROSS JOIN _SESSION.si_report_dates AS rd
  WHERE
    period_date BETWEEN DATE_SUB(rd.si_report_date, INTERVAL '89' DAY) AND rd.si_report_date
  GROUP BY
    variation_code,
    warehouse_id,
    rd.si_report_date
), dashboard_base AS (
  SELECT
    r.si_report_date AS si_report_date,
    r.snapshot_date AS period_date,
    0 AS report_type,
    r.sku AS variation_code,
    r.warehouse_id,
    IF(w.warehouse_metadata_versions = 1, w.warehouse_name, NULL) AS warehouse_name,
    IF(w.warehouse_metadata_versions = 1, w.warehouse_country, NULL) AS warehouse_country,
    w.warehouse_type,
    w.warehouse_metadata_versions,
    IF(m.metadata_versions = 1, m.metadata.product_code, NULL) AS product_code,
    IF(m.metadata_versions = 1, m.metadata.product_name, NULL) AS product_name,
    IF(m.metadata_versions = 1, m.metadata.variation_attributes, NULL) AS variation_attributes,
    IF(m.metadata_versions = 1, m.metadata.category, NULL) AS category,
    IF(m.metadata_versions = 1, m.metadata.sub_category, NULL) AS sub_category,
    IF(m.metadata_versions = 1, m.metadata.collection_bst, NULL) AS collection_bst,
    IF(m.metadata_versions = 1, m.metadata.product_launch_date, NULL) AS product_launch_date,
    IF(
      m.metadata_versions = 1,
      DATE_DIFF(r.snapshot_date, m.metadata.product_launch_date, DAY),
      NULL
    ) AS product_days_since_launch,
    IF(m.metadata_versions = 1, m.metadata.is_sale_end, NULL) AS is_sale_end,
    IF(m.metadata_versions = 1, m.metadata.retail_price, NULL) AS retail_price,
    m.metadata_versions,
    r.trial_stock AS sl_ton_kho,
    IF(m.metadata_versions = 1, r.trial_stock * m.metadata.retail_price, NULL) AS tong_gia_tri_hang_ton_kho_theo_gia_ban,
    CASE
      WHEN w.warehouse_type = 'B' AND w.warehouse_country <> 'VIETNAM'
      THEN NULL
      WHEN s.observed_sales_day_count IS NULL
      THEN 0
      ELSE s.units_sold_7d
    END AS units_sold_7d,
    CASE
      WHEN w.warehouse_type = 'B' AND w.warehouse_country <> 'VIETNAM'
      THEN NULL
      WHEN s.observed_sales_day_count IS NULL
      THEN 0
      ELSE s.units_sold_90d
    END AS units_sold_90d,
    CASE
      WHEN w.warehouse_type = 'B' AND w.warehouse_country <> 'VIETNAM'
      THEN NULL
      WHEN s.observed_sales_day_count IS NULL
      THEN 0
      ELSE s.units_sold_mtd
    END AS units_sold_mtd,
    s.observed_sales_day_count,
    s.missing_sales_qty_rows,
    r.row_origin,
    r.stock_candidate_source AS stock_source,
    r.review_status AS stock_review_status,
    r.stock_history_at,
    r.remain_stock AS history_remain_stock,
    r.actual_stock AS history_actual_stock,
    r.candidate_commitment_qty AS history_trial_commitment_qty,
    r.newer_raw_snapshot_applied,
    r.newer_raw_observation_batch,
    r.raw_observation_batch,
    r.raw_observation_age_days,
    r.history_rows_at_or_after_raw_observation,
    r.unresolved_open_line_count,
    r.returning_line_count,
    r.open_lines_with_post_cutoff_core_update,
    r.commitments_with_old_observation,
    r.cart_zero_history_trial_line_count,
    r.cart_zero_history_trial_qty,
    r.cart_zero_trial_old_observation_lines,
    r.full_return_non_commitment_line_count,
    r.full_return_missing_history_line_count,
    r.full_return_history_review_line_count,
    IFNULL(o.unresolved_history_identity_count, 0) AS unresolved_history_identity_count,
    r.raw_variation_id
  FROM stock_result AS r
  JOIN _SESSION.si_warehouse_scope AS w
    ON r.warehouse_id = w.warehouse_id
  LEFT JOIN orphan_history_audit AS o
    ON r.warehouse_id = o.warehouse_id AND o.si_report_date = r.si_report_date
  LEFT JOIN _SESSION.si_dim_groups AS m
    ON r.sku = m.variation_code
  LEFT JOIN sales_windows AS s
    ON (
      r.sku = s.variation_code AND r.warehouse_id = s.warehouse_id
    )
    AND s.si_report_date = r.si_report_date
), dashboard_metrics AS (
  SELECT
    dashboard_base.si_report_date AS si_report_date,
    *
    EXCEPT (si_report_date),
    SAFE_DIVIDE(units_sold_90d, 90) AS avg_daily_sales_90d,
    CASE
      WHEN warehouse_id = '1a21d42d-d648-4fdd-9095-932fceb08a2d'
      THEN NULL
      WHEN sl_ton_kho IS NULL OR sl_ton_kho < 0
      THEN NULL
      WHEN sl_ton_kho = 0
      THEN 0
      WHEN sl_ton_kho > 0 AND units_sold_90d > 0
      THEN SAFE_DIVIDE(sl_ton_kho * 90, units_sold_90d)
      ELSE NULL
    END AS doh,
    product_days_since_launch < 90 AS is_product_under_90d,
    CASE
      WHEN sl_ton_kho IS NULL
      THEN 'Chưa xác định số tồn'
      WHEN sl_ton_kho < 0
      THEN 'Số tồn âm cần kiểm tra'
      WHEN warehouse_metadata_versions <> 1
      THEN 'Thông tin kho mâu thuẫn'
      WHEN metadata_versions IS NULL OR metadata_versions <> 1
      THEN 'Thông tin SKU thiếu/mâu thuẫn'
      WHEN newer_raw_snapshot_applied
      THEN 'Snapshot raw mới hơn; giữ cờ coverage'
      WHEN cart_zero_history_trial_line_count > 0
      THEN 'Lượng giữ hàng từ history; cần đối chiếu'
      WHEN open_lines_with_post_cutoff_core_update > 0
      THEN 'Có cập nhật item sau ngày chốt'
      WHEN commitments_with_old_observation > 0
      THEN 'Có lượng giữ hàng từ quan sát cũ'
      ELSE 'Số thử tính; coverage chưa xác minh đầy đủ'
    END AS data_quality_note
  FROM dashboard_base
)
SELECT
  *
  EXCEPT (si_report_date, raw_variation_id),
  NOT sl_ton_kho IS NULL AS stock_is_resolved,
  COUNTIF(sl_ton_kho IS NULL) OVER (PARTITION BY dashboard_metrics.si_report_date, period_date, warehouse_id) AS warehouse_unknown_stock_rows,
  SUM(sl_ton_kho) OVER (PARTITION BY dashboard_metrics.si_report_date, period_date, warehouse_id) AS warehouse_known_stock_total,
  CASE
    WHEN sl_ton_kho IS NULL OR sl_ton_kho < 0
    THEN NULL
    WHEN sl_ton_kho = 0 OR is_sale_end = 1
    THEN 'No Stock / Sale Ended'
    WHEN warehouse_id = '1a21d42d-d648-4fdd-9095-932fceb08a2d'
    THEN NULL
    WHEN units_sold_90d = 0 AND sl_ton_kho > 0
    THEN 'Đen'
    WHEN doh > 90
    THEN 'Đỏ'
    WHEN doh > 60
    THEN 'Vàng'
    WHEN doh <= 60
    THEN 'Xanh'
    ELSE NULL
  END AS inventory_classification,
  raw_variation_id
FROM dashboard_metrics;

ASSERT (SELECT COUNT(*) FROM _SESSION.si_dashboard_result) > 0 AS 'Empty result';
-- Named SKU rows retain the original business key.
ASSERT NOT EXISTS (
  SELECT period_date, warehouse_id, variation_code
  FROM _SESSION.si_dashboard_result
  WHERE variation_code IS NOT NULL AND TRIM(variation_code) != ''
  GROUP BY period_date, warehouse_id, variation_code HAVING COUNT(*) > 1
) AS 'Duplicate named day / warehouse / SKU key';

-- Missing-SKU rows are separate source identities, never one artificial SKU.
-- Keep these rows, their raw ID and NULL stock for coverage review.
ASSERT NOT EXISTS (
  SELECT 1 FROM _SESSION.si_dashboard_result
  WHERE (variation_code IS NULL OR TRIM(variation_code) = '') AND (
    raw_variation_id IS NULL OR TRIM(raw_variation_id) = ''
    OR sl_ton_kho IS NOT NULL OR row_origin != 'additional_raw_source_key'
  )
) AS 'Missing SKU row lacks source ID or incorrectly contains a numeric stock';

ASSERT NOT EXISTS (
  SELECT period_date, warehouse_id, raw_variation_id
  FROM _SESSION.si_dashboard_result
  WHERE variation_code IS NULL OR TRIM(variation_code) = ''
  GROUP BY period_date, warehouse_id, raw_variation_id HAVING COUNT(*) > 1
) AS 'Duplicate missing-SKU source identity';
ASSERT NOT EXISTS (
  SELECT 1 FROM _SESSION.si_dashboard_result
  WHERE period_date IS NULL OR period_date NOT BETWEEN v_from_date AND v_to_date
    OR warehouse_id IS NULL OR TRIM(warehouse_id) = ''
) AS 'Invalid result date / warehouse';
ASSERT NOT EXISTS (
  SELECT si_report_date FROM _SESSION.si_report_dates
  EXCEPT DISTINCT
  SELECT period_date FROM _SESSION.si_dashboard_result
) AS 'A requested report date has no result rows';

-- V10.3 ADDITION: observed stock/empty-day streaks, calculated ONCE at refresh.
-- Meaning: elapsed calendar days in a contiguous sequence of daily snapshots with
-- stock > 0 (running) or stock = 0 (empty). First observed day = 0; next day = 1.
-- NULL/negative stock or a missing calendar date breaks continuity, never fills 0.
-- Left-censored TRUE: the start may precede the available observation sequence.
-- FALSE: the previous calendar day has a known opposite state, proving the reset.
-- These are daily snapshot streaks, NOT intraday duration, stock age or product age.
-- Full-year mode begins 01 Jan; test-range mode begins v_test_from_date. Therefore
-- test-range streaks are lower bounds and may differ from full-year streaks.
-- The 58 existing fields, inventory formulas and sales formulas are unchanged.
CREATE TEMP TABLE si_stock_day_metrics AS
WITH stock_states AS (
  SELECT period_date, warehouse_id, variation_code,
    CASE WHEN sl_ton_kho > 0 THEN 1 WHEN sl_ton_kho = 0 THEN 0 ELSE NULL END AS stock_state
  FROM _SESSION.si_dashboard_result
  WHERE variation_code IS NOT NULL AND TRIM(variation_code) != ''
  
), stock_previous AS (
  SELECT *,
    LAG(period_date) OVER stock_key AS previous_date,
    LAG(stock_state) OVER stock_key AS previous_state
  FROM stock_states
  WINDOW stock_key AS (
    PARTITION BY warehouse_id, variation_code ORDER BY period_date
  )
), stock_boundaries AS (
  SELECT *,
    CASE
      WHEN stock_state IS NULL THEN period_date
      WHEN previous_date IS NULL OR previous_state IS NULL THEN period_date
      WHEN DATE_DIFF(period_date, previous_date, DAY) != 1 THEN period_date
      WHEN stock_state != previous_state THEN period_date
      ELSE NULL
    END AS new_streak_date,
    CASE
      WHEN stock_state IS NULL THEN NULL
      WHEN previous_state IS NOT NULL
        AND DATE_DIFF(period_date, previous_date, DAY) = 1
        AND stock_state != previous_state THEN FALSE
      ELSE TRUE
    END AS start_is_left_censored
  FROM stock_previous
), stock_starts AS (
  SELECT *,
    MAX(new_streak_date) OVER (
      PARTITION BY warehouse_id, variation_code ORDER BY period_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS observed_start_date
  FROM stock_boundaries
), stock_day_values AS (
  SELECT *,
    FIRST_VALUE(start_is_left_censored) OVER (
      PARTITION BY warehouse_id, variation_code, observed_start_date
      ORDER BY period_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS observed_start_is_left_censored
  FROM stock_starts
)
SELECT period_date, warehouse_id, variation_code,
  CASE WHEN stock_state = 1 THEN DATE_DIFF(period_date, observed_start_date, DAY)
       WHEN stock_state = 0 THEN 0 ELSE NULL END AS ton_kho_running_days,
  CASE WHEN stock_state = 0 THEN DATE_DIFF(period_date, observed_start_date, DAY)
       WHEN stock_state = 1 THEN 0 ELSE NULL END AS emty_stock_days,
  IF(stock_state IS NOT NULL, observed_start_date, NULL) AS stock_streak_observed_start_date,
  IF(stock_state IS NOT NULL, observed_start_is_left_censored, NULL) AS stock_streak_is_left_censored
FROM stock_day_values;

ASSERT NOT EXISTS (
  SELECT period_date, warehouse_id, variation_code
  FROM _SESSION.si_stock_day_metrics
  GROUP BY period_date, warehouse_id, variation_code HAVING COUNT(*) > 1
) AS 'Duplicate stock-day metric key';
ASSERT (SELECT COUNT(*) FROM _SESSION.si_stock_day_metrics) = (
  SELECT COUNT(*) FROM _SESSION.si_dashboard_result
  WHERE variation_code IS NOT NULL AND TRIM(variation_code) != ''
) AS 'Stock-day calculation changed named SKU coverage';

IF v_write_full_target THEN
  CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.stock_inventory_dashboard_daily`
  PARTITION BY period_date
  CLUSTER BY warehouse_id, variation_code
  AS SELECT r.*,
    d.ton_kho_running_days, d.emty_stock_days,
    d.stock_streak_observed_start_date, d.stock_streak_is_left_censored
  FROM _SESSION.si_dashboard_result AS r
  LEFT JOIN _SESSION.si_stock_day_metrics AS d
    ON r.period_date = d.period_date AND r.warehouse_id = d.warehouse_id
    AND r.variation_code = d.variation_code;
END IF;

IF v_return_details THEN
  SELECT r.*,
    d.ton_kho_running_days, d.emty_stock_days,
    d.stock_streak_observed_start_date, d.stock_streak_is_left_censored
  FROM _SESSION.si_dashboard_result AS r
  LEFT JOIN _SESSION.si_stock_day_metrics AS d
    ON r.period_date = d.period_date AND r.warehouse_id = d.warehouse_id
    AND r.variation_code = d.variation_code;
ELSE
-- Small validation output, one row per day/warehouse.
SELECT v_write_full_target AS full_target_replacement_enabled,
  v_full_year_mode AS full_year_mode,
  v_refresh_date AS refresh_date,
  v_from_date AS refresh_from_date,
  v_to_date AS refresh_to_date,
  period_date, warehouse_id, MAX(warehouse_name) AS warehouse_name,
  COUNT(*) AS row_count, COUNT(DISTINCT variation_code) AS sku_count,
  COUNTIF(variation_code IS NULL OR TRIM(variation_code) = '') AS missing_sku_rows,
  COUNT(DISTINCT IF(variation_code IS NULL OR TRIM(variation_code) = '',
    raw_variation_id, NULL)) AS missing_sku_raw_id_count,
  COUNTIF(sl_ton_kho IS NULL) AS unknown_stock_rows,
  COUNTIF(sl_ton_kho < 0) AS negative_stock_rows,
  SUM(sl_ton_kho) AS known_total_stock,
  COUNTIF(open_lines_with_post_cutoff_core_update > 0) AS rows_with_post_cutoff_core_update,
  COUNTIF(missing_sales_qty_rows > 0) AS rows_with_missing_sales_quantity,
  COUNTIF(metadata_versions IS NULL OR metadata_versions != 1) AS rows_with_metadata_issue
FROM _SESSION.si_dashboard_result
GROUP BY period_date, warehouse_id ORDER BY period_date, warehouse_name;
END IF;

END;
