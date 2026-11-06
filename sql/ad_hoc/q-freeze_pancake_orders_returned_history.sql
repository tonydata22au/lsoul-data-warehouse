-- One-time freeze of Pancake return orders that predate raw.raw_orders_returned
-- (decision D1, 2026-11-05). PREPARED, NOT RUN: writes a new table in raw. Run once,
-- with the owner's approval, before the first dbt build or full refresh of core_pancake__orders_returned
-- (lsoul_dbt source pancake.raw_orders_returned_history).
--
-- Cutover 2026-02-11 is the first raw window start: the earliest raw load (2026-03-12) covers
-- max(date(inserted_at)) - 28 days. On 2026-11-05 the live table held 728 rows before it
-- (2025-06-11 … 2026-02-10). Re-running fails at CREATE TABLE instead of duplicating rows.

CREATE TABLE `marine-cycle-484213-b4.raw.raw_orders_returned_history`
(
  inserted_at DATETIME,
  display_id INT64,
  status INT64,
  bill_full_name STRING,
  customer_id STRING,
  updated_at DATETIME,
  creator_id STRING,
  order_id INT64,
  order_to_returned_id STRING,
  is_duplicate INT64
)
PARTITION BY _PARTITIONDATE
OPTIONS (
  description = 'Frozen copy of core_pancake.core_orders_returned rows dated before 2026-02-11 (first raw window). One-time load; read by lsoul_dbt stg_pancake__orders_returned_history.'
);

INSERT INTO `marine-cycle-484213-b4.raw.raw_orders_returned_history`
  (inserted_at, display_id, status, bill_full_name, customer_id, updated_at, creator_id,
   order_id, order_to_returned_id, is_duplicate)
SELECT inserted_at, display_id, status, bill_full_name, customer_id, updated_at, creator_id,
       order_id, order_to_returned_id, is_duplicate
FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned`
WHERE DATE(inserted_at) < DATE '2026-02-11';

ASSERT (
  SELECT COUNT(*) FROM `marine-cycle-484213-b4.raw.raw_orders_returned_history`
) = (
  SELECT COUNT(*) FROM `marine-cycle-484213-b4.core_pancake.core_orders_returned`
  WHERE DATE(inserted_at) < DATE '2026-02-11'
) AS 'frozen history row count differs from the live table';
