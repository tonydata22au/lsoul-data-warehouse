CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.sysdb.sp_data_insert_log`(i_date_source_col_name STRING, i_date_target_col_name STRING, i_number_interval_day INT64, i_dataset_name STRING, i_table_name STRING, i_store_procedure_name STRING, i_store_procedure_dataset STRING, i_full_source_table_name STRING, i_full_target_table_name STRING, i_full_store_procedure_name STRING, i_full_raw_table_name STRING)
BEGIN
/*
Author: Toan Pham
Date: 27/04/2026
Comment: This store procedure is to insert the log data to table sysdb.sp_data_insert_log

Param Format Guide:
i_date_source_col_name: 'inserted_at' --normally in stg table
i_date_col_name : 'inserted_at'
i_number_interval_day: 1 -- 1 day
i_dataset_name: sysdb
i_table_name: data_insert_log
i_store_procedure_name: sp_data_insert_log
i_store_procedure_dataset: sysdb
i_full_source_table_name: 'marine-cycle-484213-b4.sysdb.stg_table'
i_full_target_table_name: 'marine-cycle-484213-b4.sysdb.data_insert_log'
i_full_store_procedure_name: `marine-cycle-484213-b4.sysdb.sp_data_insert_log`
i_full_raw_table_name: RAW TABLE

Run syntax: 
  CALL `marine-cycle-484213-b4.sysdb.sp_data_insert_log_V2`() 
*/
  DECLARE is_success INT64;
  DECLARE data_proc_date DATE;
  DECLARE data_insert_from_date DATE;
  DECLARE data_insert_to_date DATE;
  DECLARE sql_from STRING;
  DECLARE sql_to   STRING;
  DECLARE sql_last_proc_date STRING;
  DECLARE sql_raw_proc_date STRING;

  --data_proc_date
  SET sql_raw_proc_date = FORMAT("""
    SELECT COUNT(1)
    FROM`%s`
    WHERE DATE(_PARTITIONTIME) = CURRENT_DATE()
  """,
    i_full_raw_table_name
  );

  EXECUTE IMMEDIATE sql_raw_proc_date INTO is_success;


  --data_proc_date
  SET sql_last_proc_date = FORMAT("""
    SELECT MAX(DATE(proc_date)) AS max_proc_date
    FROM`%s`
    WHERE DATE(proc_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL %i DAY)
  """,
    i_full_source_table_name,
    i_number_interval_day
  );

  EXECUTE IMMEDIATE sql_last_proc_date INTO data_proc_date;

  --data_insert_from_date from source table
  SET sql_from = FORMAT("""
    SELECT MIN(DATE(%s)) AS max_dt
    FROM`%s`
    WHERE DATE(proc_date) = CURRENT_DATE()
  """,
    i_date_source_col_name,
    i_full_source_table_name
  );

  EXECUTE IMMEDIATE sql_from INTO data_insert_from_date;

  --data_insert_to_date from target table
  SET sql_to = FORMAT("""
    SELECT MAX(DATE(%s)) AS max_dt
    FROM `%s`
    WHERE DATE(%s) >= DATE_SUB(CURRENT_DATE(), INTERVAL %i DAY)
  """, 
    i_date_target_col_name,
    i_full_target_table_name,
    i_date_target_col_name,
    i_number_interval_day
   );

  EXECUTE IMMEDIATE sql_to INTO data_insert_to_date;

  -- From here on you can use static INSERT, since the log table is fixed
  IF data_proc_date = DATE(CURRENT_DATE) THEN
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
      CASE WHEN is_success > 0 THEN 1 ELSE 0 END, -- is_success
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
      CASE WHEN is_success > 0 THEN 1 ELSE 0 END, -- is_success
      data_insert_from_date,
      data_insert_to_date,
      i_store_procedure_name,
      i_store_procedure_dataset,
      i_full_target_table_name,
      i_full_store_procedure_name
    );
  END IF;
END;