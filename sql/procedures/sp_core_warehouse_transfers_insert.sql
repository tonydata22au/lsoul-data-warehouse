CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.core_pancake.sp_core_warehouse_transfers_insert`(IN i_inserted_at_date STRING)
BEGIN
/*
Author: Toan Pham
Date: 09/02/2026
Comment: This store procedure is to insert the data from stg_warehouse_transfers_completed -> ore_warehouse_transfers_completed_import
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_core_warehouse_transfers_insert`('') --today date
  CALL `marine-cycle-484213-b4.core_pancake.sp_core_warehouse_transfers_insert`('2026-02-08') --specify the date
*/
  DECLARE converted_date DATE DEFAULT 
    CASE 
      WHEN i_inserted_at_date IS NULL OR i_inserted_at_date = '' THEN DATE_ADD(CURRENT_DATE(), INTERVAL -1 DAY)
      ELSE PARSE_DATE('%Y-%m-%d', i_inserted_at_date)
    END;

INSERT INTO `marine-cycle-484213-b4.core_pancake.core_warehouse_transfers_completed_import`
(
  proc_date,
  inserted_at,
  warehouse_transfer_id, 
  warehouse_transfer_display_id,
  status, 
  updated_status_at, 
  from_warehouse_id, 
  from_warehouse_name, 
  to_warehouse_id, 
  to_warehouse_name, 
  creator_name, 
  shipping_fee, 
  total_quantity
)
SELECT DISTINCT
  proc_date,
  inserted_at,
  warehouse_transfer_id, 
  warehouse_transfer_display_id,
  status, 
  updated_status_at, 
  from_warehouse_id, 
  from_warehouse_name, 
  to_warehouse_id, 
  to_warehouse_name, 
  creator_name, 
  shipping_fee, 
  total_quantity
FROM `marine-cycle-484213-b4.stg_pancake.stg_warehouse_transfers_completed`
WHERE DATE(inserted_at) = converted_date;
END;