CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.core_pancake.sp_core_orders_returned_insert`(IN i_proc_date STRING)
BEGIN
/*
Author: Toan Pham
Date: 09/02/2026
Comment: This store procedure is to insert the data from raw_orders_returned` -> stg_orders_returned
Run syntax: 
  CALL `marine-cycle-484213-b4.core_pancake.sp_core_orders_returned_insert`('') --today date
  CALL `marine-cycle-484213-b4.core_pancake.sp_core_orders_returned_insert`('2026-02-08') --specify the date
*/
  
  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.stg_pancake.stg_orders_returned`);

  DECLARE data_insert_to_date DATE DEFAULT
                                              (SELECT MAX(DATE(inserted_at)) 
                                              FROM `marine-cycle-484213-b4.stg_pancake.stg_orders_returned`);
  DECLARE data_insert_from_date DATE DEFAULT
                                            DATE_SUB(
                                              (SELECT MAX(DATE(inserted_at)) 
                                              FROM `marine-cycle-484213-b4.stg_pancake.stg_orders_returned`),
                                              INTERVAL 28 DAY
                                            );

  IF data_proc_date = DATE(CURRENT_DATE) THEN

DELETE `marine-cycle-484213-b4.core_pancake.core_orders_returned` WHERE DATE(inserted_at) >= data_insert_from_date;
    

INSERT INTO `marine-cycle-484213-b4.core_pancake.core_orders_returned`
(
inserted_at, 
display_id, 
status, 
bill_full_name, 
customer_id, 
updated_at, 
creator_id, 
order_id, 
order_to_returned_id, 
is_duplicate
)
WITH CTE AS (
SELECT DISTINCT
inserted_at, 
display_id, 
status, 
bill_full_name, 
customer_id, 
updated_at, 
creator_id, 
order_id, 
order_to_returned_id
FROM `marine-cycle-484213-b4.stg_pancake.stg_orders_returned`
WHERE DATE(inserted_at) >= data_insert_from_date AND DATE(proc_date) = data_proc_date
AND order_id is not null
)
SELECT
*
,CASE WHEN RANK() OVER (PARTITION BY order_to_returned_id ORDER BY display_id DESC, inserted_at DESC) > 1 THEN 1 ELSE 0 END AS is_duplicate
FROM CTE;

CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'inserted_at'
  ,1
  ,'core_pancake'
  ,'core_orders_returned'
  ,'sp_core_orders_returned_insert'
  ,'core_pancake'  
  ,'marine-cycle-484213-b4.stg_pancake.stg_orders_returned'
  ,'marine-cycle-484213-b4.core_pancake.core_orders_returned'
  ,'marine-cycle-484213-b4.core_pancake.sp_core_orders_returned_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_orders_returned'
);

  ELSE 

  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V3`( 
  'inserted_at'
  ,'inserted_at'
  ,1
  ,'core_pancake'
  ,'core_orders_returned'
  ,'sp_core_orders_returned_insert'
  ,'core_pancake'  
  ,'marine-cycle-484213-b4.stg_pancake.stg_orders_returned'
  ,'marine-cycle-484213-b4.core_pancake.core_orders_returned'
  ,'marine-cycle-484213-b4.core_pancake.sp_core_orders_returned_insert'
  ,'marine-cycle-484213-b4.raw_pancake.raw_orders_returned'
);



END IF;

END;