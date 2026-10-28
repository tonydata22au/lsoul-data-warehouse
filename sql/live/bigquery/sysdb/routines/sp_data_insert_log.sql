CREATE PROCEDURE `marine-cycle-484213-b4`.sysdb.sp_data_insert_log(i_date_col_name STRING, i_number_interval_day INT64, i_dataset_name STRING, i_table_name STRING, i_store_procedure_name STRING, i_store_procedure_dataset STRING, i_full_target_table_name STRING, i_full_store_procedure_name STRING)
BEGIN
/*
Author: Toan Pham
Date: 09/02/2026
Comment: This store procedure is to insert the log data to table sysdb.sp_data_insert_log

Param Format Guide:
i_date_col_name : 'insert_at'
i_number_interval_day: 1 -- 1 day
i_dataset_name: sysdb
i_table_name: data_insert_log
i_store_procedure_name: sp_data_insert_log
i_store_procedure_dataset: sysdb
i_full_target_table_name: `marine-cycle-484213-b4.sysdb.data_insert_log`
i_full_store_procedure_name: `marine-cycle-484213-b4.sysdb.sp_data_insert_log`

Run syntax: 
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log`() 
*/
  DECLARE data_insert_from_date DATE;
  DECLARE data_insert_to_date DATE;
  DECLARE sql_from STRING;
  DECLARE sql_to   STRING;

  -- Build dynamic SQL to get MAX(date(i_date_col_name)) from target table
  SET sql_from = FORMAT("""
    SELECT MAX(DATE(%s)) AS max_dt
    FROM`%s`
  """,
    i_date_col_name,
    i_full_target_table_name
  );

  EXECUTE IMMEDIATE sql_from INTO data_insert_from_date;
  SET data_insert_from_date = DATE_SUB(data_insert_from_date, INTERVAL i_number_interval_day DAY);

  -- Build dynamic SQL to get MAX(DATE(inserted_at)) from target table
  -- If the column name is also passed in, use i_date_col_name instead of hard‑coding inserted_at
  SET sql_to = FORMAT("""
    SELECT MAX(DATE(%s)) AS max_dt
    FROM `%s`
  """, 
    i_date_col_name,
    i_full_target_table_name
   );

  EXECUTE IMMEDIATE sql_to INTO data_insert_to_date;

  -- From here on you can use static INSERT, since the log table is fixed
  IF data_insert_to_date = DATE_SUB(CURRENT_DATE(), INTERVAL i_number_interval_day DAY) THEN
    INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log`
    (
      proc_date,
      source_table_dataset,
      source_table_name,
      is_today,
      is_success,
      inserted_frDate,
      inserted_toDate,
      store_procedure_name,
      store_procedure_dataset,
      full_source_table_name,
      full_store_procedure_name
    )
    VALUES
    (
      CURRENT_DATETIME('Asia/Ho_Chi_Minh'),
      i_dataset_name,
      i_table_name,
      1, -- is_today
      1, -- is_success
      data_insert_from_date,
      data_insert_to_date,
      i_store_procedure_name,
      i_store_procedure_dataset,
      i_full_target_table_name,
      i_full_store_procedure_name
    );
  ELSE
    INSERT INTO `marine-cycle-484213-b4.sysdb.data_insert_log`
    (
      proc_date,
      source_table_dataset,
      source_table_name,
      is_today,
      is_success,
      inserted_frDate,
      inserted_toDate,
      store_procedure_name,
      store_procedure_dataset,
      full_source_table_name,
      full_store_procedure_name
    )
    VALUES
    (
      CURRENT_DATETIME('Asia/Ho_Chi_Minh'),
      i_dataset_name,
      i_table_name,
      0, -- is_today
      0, -- is_success
      data_insert_from_date,
      data_insert_to_date,
      i_store_procedure_name,
      i_store_procedure_dataset,
      i_full_target_table_name,
      i_full_store_procedure_name
    );
  END IF;
END;
