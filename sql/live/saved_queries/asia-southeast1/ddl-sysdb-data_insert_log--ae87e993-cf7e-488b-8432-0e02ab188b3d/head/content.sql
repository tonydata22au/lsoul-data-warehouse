CREATE OR REPLACE TABLE `marine-cycle-484213-b4.sysdb.data_insert_log`
(
  proc_date                  DATETIME,
  source_table_dataset       STRING,
  source_table_name          STRING,
  is_today                   INT64,
  is_success                 INT64,   -- BigQuery has no TINYINT; INT64 covers it
  inserted_frDate            DATE,
  inserted_toDate            DATE,
  store_procedure_name       STRING,
  store_procedure_dataset    STRING,
  full_source_table_name     STRING,
  full_store_procedure_name  STRING
);



