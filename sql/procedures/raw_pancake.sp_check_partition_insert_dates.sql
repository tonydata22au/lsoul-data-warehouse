CREATE OR REPLACE PROCEDURE `marine-cycle-484213-b4.raw_pancake.sp_check_partition_insert_dates`(is_filter_today INT64, filter_tables ARRAY<STRING>)
BEGIN
  DECLARE tables_with_col_has_inserted_at ARRAY<STRING>;
  DECLARE tables_with_col_no_inserted_at ARRAY<STRING>;
  DECLARE dynamic_query STRING DEFAULT '';
  DECLARE dynamic_query2 STRING DEFAULT '';
  DECLARE final_query STRING DEFAULT '';
  DECLARE i INT64 DEFAULT 0;
  DECLARE j INT64 DEFAULT 0;

  -- Filter by specific tables if provided
  SET tables_with_col_has_inserted_at = (
    SELECT ARRAY_AGG(DISTINCT table_name)
    FROM `marine-cycle-484213-b4.raw_pancake.INFORMATION_SCHEMA.COLUMNS`
    WHERE column_name = 'inserted_at'
      AND (ARRAY_LENGTH(filter_tables) = 0 OR table_name IN UNNEST(filter_tables))
  );

  -- Populate array with table names NOT having 'inserted_at'
  SET tables_with_col_no_inserted_at = (
    SELECT ARRAY_AGG(DISTINCT table_name)
    FROM (
      SELECT DISTINCT table_name
      FROM `marine-cycle-484213-b4.raw_pancake.INFORMATION_SCHEMA.COLUMNS`
      WHERE table_name LIKE 'raw_%' 
        AND (ARRAY_LENGTH(filter_tables) = 0 OR table_name IN UNNEST(filter_tables))
    ) AS all_raw_tables
    WHERE table_name NOT IN UNNEST(IFNULL(tables_with_col_has_inserted_at, []))
) ;

  -- Build UNION ALL query
  WHILE i < ARRAY_LENGTH(tables_with_col_has_inserted_at) DO
    IF i > 0 THEN
      SET dynamic_query = CONCAT(dynamic_query, ' UNION ALL ');
    END IF;
    
    SET dynamic_query = CONCAT(
      dynamic_query,
      'SELECT \'', tables_with_col_has_inserted_at[OFFSET(i)], '\' AS source_table, ',
    'CASE WHEN DATE_TRUNC(CURRENT_DATE(), DAY) = DATE(_PARTITIONTIME, \'Asia/Ho_Chi_Minh\') THEN 1 ELSE 0 END AS is_today, ',
    '1 AS has_inserted_at, ',
    'DATE(_PARTITIONTIME, \'Asia/Ho_Chi_Minh\')  AS proc_date, ',
    'DATETIME(PARSE_TIMESTAMP(\'%Y%m%d%H%M%S\', MAX(inserted_at))) AS insert_toDate, ',
    'DATETIME(PARSE_TIMESTAMP(\'%Y%m%d%H%M%S\', MIN(inserted_at))) AS insert_frDate ',
    'FROM `marine-cycle-484213-b4.raw_pancake.', tables_with_col_has_inserted_at[OFFSET(i)], '` ',
    'WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2020-02-08") ',
    'GROUP BY 1, 2, 3, 4'
  );
    
    SET i = i + 1;
  END WHILE;

  -- Build UNION ALL query for tables WITHOUT inserted_at
WHILE j < ARRAY_LENGTH(tables_with_col_no_inserted_at) DO
  IF LENGTH(dynamic_query2) > 0 THEN
    SET dynamic_query2 = CONCAT(dynamic_query2, ' UNION ALL ');
  END IF;
  
  SET dynamic_query2 = CONCAT(
    dynamic_query2,
    'SELECT \'', tables_with_col_no_inserted_at[OFFSET(j)], '\' AS source_table, ',
    'CASE WHEN DATE_TRUNC(CURRENT_DATE(), DAY) = DATE(_PARTITIONTIME, \'Asia/Ho_Chi_Minh\')  THEN 1 ELSE 0 END AS is_today, ',
    '0 AS has_inserted_at, ',
    'DATE(_PARTITIONTIME, \'Asia/Ho_Chi_Minh\') AS proc_date, ',
    'DATETIME(MAX(TIMESTAMP_TRUNC(_PARTITIONTIME, DAY))) AS insert_toDate, ',
    'DATETIME(MIN(TIMESTAMP_TRUNC(_PARTITIONTIME, DAY))) AS insert_frDate ',
    'FROM `marine-cycle-484213-b4.raw_pancake.', tables_with_col_no_inserted_at[OFFSET(j)], '` ',
    'WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP("2020-02-08") ',
    'GROUP BY 1, 2, 3, 4'
  );
  
  SET j = j + 1;
END WHILE;

  -- Combine both queries properly
IF LENGTH(dynamic_query) > 0 AND LENGTH(dynamic_query2) > 0 THEN
  -- Both queries have content
  SET final_query = CONCAT(dynamic_query, ' UNION ALL ', dynamic_query2);
ELSEIF LENGTH(dynamic_query) > 0 THEN
  -- Only first query has content
  SET final_query = dynamic_query;
ELSEIF LENGTH(dynamic_query2) > 0 THEN
  -- Only second query has content
  SET final_query = dynamic_query2;
ELSE
  -- No tables found - create a simple error message query
  SET final_query = 'SELECT "No tables found" AS error_message';
END IF;

  -- Apply filtering and ordering based on is_filter_today parameter
IF is_filter_today = 1 THEN
    -- Wrap the entire UNION ALL in a CTE and filter for today only
  SET final_query = CONCAT(
      'CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_pancake.partition_insert_dates_today` AS WITH CTE AS (', 
      final_query, 
      ') SELECT * FROM CTE WHERE is_today = 1 ORDER BY 1 ASC, 2 DESC, 3 DESC, 4 DESC'
    );
  ELSE
    -- Just add ORDER BY without filtering
    SET final_query = CONCAT(
      'CREATE OR REPLACE TABLE `marine-cycle-484213-b4.raw_pancake.partition_insert_dates_all` AS ',
      final_query, 
      ' ORDER BY 1 ASC, 2 DESC, 3 DESC, 4 DESC'
    );
  END IF;

  -- Execute the dynamic query
  EXECUTE IMMEDIATE final_query;

END;