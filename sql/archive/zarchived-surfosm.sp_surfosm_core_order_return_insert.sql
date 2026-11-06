CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4`.surfosm.sp_surfosm_core_order_return_insert()
BEGIN
/*
Author: Toan Pham
Date: 02/05/2026
Comment: This store procedure is to insert the data from stg_surfosm_order_return -> core_surfosm_order_return
Run syntax: 
  CALL `marine-cycle-484213-b4.surfosm.sp_surfosm_core_order_return_insert`() --today date
*/

  DECLARE data_proc_date DATE DEFAULT
                                      (SELECT MAX(DATE(proc_date)) FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order_return`);

  DECLARE data_insert_to_date DATE DEFAULT
                                              (SELECT MAX(parameter_date) 
                                              FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order_return`
                                              WHERE DATE(proc_date) = data_proc_date);
  DECLARE data_insert_from_date DATE DEFAULT
                                              (SELECT MIN(parameter_date)
                                              FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order_return`
                                              WHERE DATE(proc_date) = data_proc_date);

  IF data_proc_date = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh")) THEN

  DELETE `marine-cycle-484213-b4.surfosm.core_surfosm_order_return` WHERE parameter_date >= data_insert_from_date;
    
  INSERT INTO `marine-cycle-484213-b4.surfosm.core_surfosm_order_return`
  (
  parameter_date,
  order_number,
  external_order_id,
  channel,
  shipping,
  total_returns,
  returns_return_document_code,
  returns_order_number,
  returns_type_cancel,
  returns_qty,
  returns_received,
  returns_status,
  returned_product_sku,
  returned_product_code,
  returned_product_name,
  returned_product_lot_number,
  returned_product_quantity,
  returned_product_status
  )
  SELECT DISTINCT
  parameter_date,
  order_number,
  external_order_id,
  channel,
  shipping,
  total_returns,
  returns_return_document_code,
  returns_order_number,
  returns_type_cancel,
  returns_qty,
  returns_received,
  returns_status,
  IFNULL(returns_detail_item_item_sku,returns_detail_item_item_code) AS returned_product_sku,
  REGEXP_EXTRACT(returns_detail_item_item_code, r'^([^-]+)') AS returned_product_code,
  returns_detail_item_i_name AS returned_product_name,
  returns_detail_item_lot_number AS returned_product_lot_number,
  returns_detail_item_item_quantity AS returned_product_quantity,
  returns_detail_item_status_item AS returned_product_status
  FROM `marine-cycle-484213-b4.surfosm.stg_surfosm_order_return`
  WHERE parameter_date >= data_insert_from_date AND DATE(proc_date) = DATE(CURRENT_DATE("Asia/Ho_Chi_Minh"));
  
  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'surfosm'
            ,'core_surfosm_order_return'
            ,1
            ,1
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_surfosm_core_order_return_insert'
            ,'surfosm'
            ,'marine-cycle-484213-b4.surfosm.core_surfosm_order_return'
            ,'marine-cycle-484213-b4.surfosm.sp_surfosm_core_order_return_insert'
          );

  ELSE 

  INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log` 
  VALUES (
            current_datetime('Asia/Ho_Chi_Minh')
            ,'surfosm'
            ,'core_surfosm_order_return'
            ,0
            ,0
            ,data_insert_from_date
            ,data_insert_to_date
            ,'sp_surfosm_core_order_return_insert'
            ,'surfosm'
            ,'marine-cycle-484213-b4.surfosm.core_surfosm_order_return'
            ,'marine-cycle-484213-b4.surfosm.sp_surfosm_core_order_return_insert'
          );
  END IF;
END;
