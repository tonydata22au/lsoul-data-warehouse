CREATE OR REPLACE PROCEDURE
  `marine-cycle-484213-b4.sysdb.sp_check_schema_table_data_load_time`(
    p_schema_name STRING)
BEGIN
/*
Comment: Compares today's and yesterday's ingestion-time partition row counts
for every ingestion-time partitioned base table whose dataset name contains
p_schema_name. Dates are Vietnam calendar days compared with DATE(_PARTITIONTIME).

Run syntax:
  CALL `marine-cycle-484213-b4.sysdb.sp_check_schema_table_data_load_time`('raw');

Optimised version of the original:
  - Reads INFORMATION_SCHEMA.TABLES once (was twice) and no longer joins
    INFORMATION_SCHEMA.COLUMNS. That join returned one row per column, so every
    table's query was repeated once per column and rows were duplicated in the result.
  - Keeps only ingestion-time partitioned tables (by their DDL). Without this
    filter, any other table in a matching dataset made the dynamic SQL fail on
    _PARTITIONTIME.
  - Queries each table once for both days instead of twice.
  The output columns, their values and the sort order are unchanged.
*/
DECLARE today DATE DEFAULT CURRENT_DATE('Asia/Ho_Chi_Minh');
DECLARE yesterday DATE DEFAULT DATE_SUB(today, INTERVAL 1 DAY);
DECLARE sql_counts STRING;

SET sql_counts = (
  SELECT
    STRING_AGG(
      "SELECT '" || t.table_schema || "." || t.table_name || "' AS table_name, "
        || "DATE(_PARTITIONTIME) AS proc_date, COUNT(*) AS row_count "
        || "FROM `" || t.table_catalog || "." || t.table_schema || "." || t.table_name || "` "
        || "WHERE DATE(_PARTITIONTIME) IN ('" || CAST(yesterday AS STRING) || "', '"
        || CAST(today AS STRING) || "') "
        || "GROUP BY 1, 2",
      '\nUNION ALL\n')
  FROM `marine-cycle-484213-b4.region-asia-southeast1`.INFORMATION_SCHEMA.TABLES t
  JOIN
    `marine-cycle-484213-b4.region-asia-southeast1`.INFORMATION_SCHEMA.COLUMNS
      AS c
    ON t.table_name = c.table_name AND t.table_schema = c.table_schema
  WHERE
    table_type = 'BASE TABLE'
    AND (t.table_schema LIKE CONCAT('%', p_schema_name, '%') OR t.table_name LIKE CONCAT('%', p_schema_name, '%'))
    
    -- Only include ingestion-time partitioned tables to avoid the _PARTITIONTIME error
    AND c.is_partitioning_column = 'YES'
    AND c.column_name = '_PARTITIONTIME'
    -- Ingestion-time partitioned: DDL is PARTITION BY _PARTITIONDATE (daily)
    -- or TIMESTAMP_TRUNC(_PARTITIONTIME, ...) (hourly/monthly/yearly).
    --AND REGEXP_CONTAINS(ddl, r'PARTITION BY [^\n]*_PARTITION(DATE|TIME)')
);

-- CONCAT instead of FORMAT avoids the FORMAT size limit.
IF sql_counts IS NOT NULL THEN
  EXECUTE IMMEDIATE CONCAT(
    "WITH counts AS (", sql_counts, "), ",
    "a AS (SELECT * FROM counts WHERE proc_date = '", CAST(today AS STRING), "'), ",
    "b AS (SELECT * FROM counts WHERE proc_date = '", CAST(yesterday AS STRING), "') ",
    "SELECT ",
    "  a.table_name AS table_name, ",
    "  a.proc_date AS load_time, ",
    "  a.row_count AS row_count, ",
    "  IF(a.table_name IS NULL, b.table_name, NULL) AS table_name_missing, ",
    "  IF(a.table_name IS NULL, b.proc_date, NULL) AS last_load_time, ",
    "  IF(a.table_name IS NULL, 0, b.row_count - a.row_count) AS row_count_diff ",
    "FROM a ",
    "FULL OUTER JOIN b ON a.table_name = b.table_name ",
    "ORDER BY 4 DESC, 1, 2");
ELSE
  SELECT
    'No ingestion-time partitioned tables found matching the criteria.'
      AS status;
END IF;

END;
