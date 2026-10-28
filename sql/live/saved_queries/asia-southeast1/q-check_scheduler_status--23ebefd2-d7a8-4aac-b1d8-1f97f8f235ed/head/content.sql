DECLARE tables_has_col_inserted_at ARRAY<STRING>;
DECLARE tables_has_no_col_inserted_at ARRAY<STRING>;
DECLARE dynamic_query STRING DEFAULT '';
DECLARE dynamic_query2 STRING DEFAULT '';
DECLARE final_query STRING DEFAULT '';
DECLARE i INT64 DEFAULT 0;
DECLARE j INT64 DEFAULT 0;

-- Populate array with table names having 'inserted_at'
SET tables_has_col_inserted_at = (
  SELECT ARRAY_AGG(DISTINCT table_name)
  FROM `marine-cycle-484213-b4.raw_pancake.INFORMATION_SCHEMA.COLUMNS`
  WHERE column_name = 'inserted_at'
);

-- Populate array with table names NOT having 'inserted_at'
SET tables_has_no_col_inserted_at = (
  SELECT ARRAY_AGG(table_name)
  FROM (
    SELECT DISTINCT table_name
    FROM `marine-cycle-484213-b4.raw_pancake.INFORMATION_SCHEMA.TABLES`
    WHERE table_name LIKE 'raw_%'
  ) AS all_raw_tables
  WHERE table_name NOT IN UNNEST(IFNULL(tables_has_col_inserted_at, []))
);

-- Build UNION ALL query for tables WITH inserted_at
WHILE i < ARRAY_LENGTH(tables_has_col_inserted_at) DO
  IF i > 0 THEN
    SET dynamic_query = CONCAT(dynamic_query, ' UNION ALL ');
  END IF;
  
  SET dynamic_query = 
    CONCAT(
      dynamic_query, 
      FORMAT(
              '''
              SELECT 
                '%s' AS source_table,
                CASE
                  WHEN DATE_TRUNC(CURRENT_DATE(), DAY)
                      = DATE(_PARTITIONTIME, 'Asia/Ho_Chi_Minh')
                  THEN 1 ELSE 0
                END AS is_today,
                1 AS has_inserted_at,
                DATE(_PARTITIONTIME, 'Asia/Ho_Chi_Minh') AS proc_date,
                DATETIME(PARSE_TIMESTAMP('%%Y%%m%%d%%H%%M%%S', MAX(inserted_at))) AS insert_toDate,
                DATETIME(PARSE_TIMESTAMP('%%Y%%m%%d%%H%%M%%S', MIN(inserted_at))) AS insert_frDate
              FROM `marine-cycle-484213-b4.raw_pancake.%s`
              WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP('2020-02-08')
              GROUP BY 1, 2, 3, 4 
              ''',
                tables_has_col_inserted_at[OFFSET(i)],
                tables_has_col_inserted_at[OFFSET(i)]
            )
          );

  SET i = i + 1;
END WHILE;

-- Build UNION ALL query for tables WITHOUT inserted_at
WHILE j < ARRAY_LENGTH(tables_has_no_col_inserted_at) DO
  IF LENGTH(dynamic_query2) > 0 THEN
    SET dynamic_query2 = CONCAT(dynamic_query2, ' UNION ALL ');
  END IF;
  
  SET dynamic_query2 = CONCAT(
    dynamic_query2,
    FORMAT(
              '''
              SELECT 
                '%s' AS source_table,
                CASE
                  WHEN DATE_TRUNC(CURRENT_DATE(), DAY)
                      = DATE(_PARTITIONTIME, 'Asia/Ho_Chi_Minh')
                  THEN 1 ELSE 0
                END AS is_today,
                1 AS has_inserted_at,
                DATE(_PARTITIONTIME, 'Asia/Ho_Chi_Minh') AS proc_date,
                NULL AS insert_toDate,
                NULL AS insert_frDate
              FROM `marine-cycle-484213-b4.raw_pancake.%s`
              WHERE TIMESTAMP_TRUNC(_PARTITIONTIME, DAY) >= TIMESTAMP('2020-02-08')
              GROUP BY 1, 2, 3, 4 
              ''',
                tables_has_no_col_inserted_at[OFFSET(j)],
                tables_has_no_col_inserted_at[OFFSET(j)]
            )
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

  SET final_query = CONCAT(
    'WITH CTE AS (',
    final_query,
    ')',
    FORMAT(
      '''
      SELECT
      ROW_NUMBER() OVER (PARTITION BY source_table ORDER BY proc_date DESC) AS sort_order,
      *
      FROM CTE
      '''
    )
  );


-- Execute the dynamic query
EXECUTE IMMEDIATE final_query;
