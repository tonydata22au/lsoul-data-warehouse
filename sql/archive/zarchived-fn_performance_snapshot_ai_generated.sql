CREATE OR REPLACE TABLE FUNCTION `marine-cycle-484213-b4.reportdb.fn_performance_snapshot_ai_generated`(
  i_type INT64 -- not set yet
  ,i_number_month_back INT64 --0: current month
)
AS 
/*
Author: Toan Pham
Date: 04/08/2026
Comment: 

Endpoint Name	Model / Use Case	Description
gemini-2.5-flash (Default):	Fast & Balanced	The default model if no endpoint is specified. Optimized for high-throughput speed, cost efficiency, and general multimodal tasks.

gemini-1.5-flash:	Lightweight & High Speed

Testing:
  SELECT * FROM `marine-cycle-484213-b4.reportdb.fn_performance_snapshot_ai_generated`(0,2) 

*/
(
-- Step 1: Pre-aggregate data by Week and Country to massively reduce text size
WITH AggregatedMetrics AS (
  SELECT 
    period_date
    , country
    , level_2
    , level_3
    ,SUM(order_confirmed) AS order_confirmed
    ,SUM(customers) AS total_customers
    ,COUNT(distinct product_name) AS sku_qty
    ,SUM(units_sold) AS units_sold
    , SUM(sales_revenue) AS sales_revenue
    , SUM(revenue) AS revenue
    ,SUM(target_revenue_per_level_3) AS target_revenue
    FROM `marine-cycle-484213-b4.reportdb.report_performancce_snapshot` 
    WHERE 1=1
    AND DATE(period_date) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL i_number_month_back MONTH)
    AND DATE(period_date) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    GROUP BY 
    1,2,3,4
),

-- Step 2: Form a clean, dense text summary block
DatasetSummary AS (
  SELECT 
    STRING_AGG(
      CONCAT(
          'period_date: ', CAST(period_date AS STRING),
          -- ' | month_start: ', CAST(month_start AS STRING),
          -- ' | week_start: ', CAST(week_start AS STRING),
          -- ' | order_week: ', CAST(order_week AS STRING),
          ' | country: ', country,
          --' | level_1: ', level_1,
          ' | level_2: ', level_2,
          ' | level_3: ', level_3,



          -- ' | product_code: ', product_code,
          -- ' | product_name: ', product_name,
          -- ' | variation_code: ', variation_code,
          -- ' | variation_attributes: ', variation_attributes,
          -- ' | retail_price: ', CAST(retail_price AS STRING),
          -- ' | warehouse_id: ', CAST(warehouse_id AS STRING),
          -- ' | warehouse_name: ', warehouse_name,
           ' | target_revenue: ', CAST(target_revenue AS STRING),
          -- ' | original_sales_revenue: ', CAST(original_sales_revenue AS STRING),
           ' | sales_revenue: ', CAST(sales_revenue AS STRING),
           ' | revenue: ', CAST(revenue AS STRING),
           ' | units_sold: ', CAST(units_sold AS STRING),
           ' | order_confirmed: ', CAST(order_confirmed AS STRING),
           ' | total_number_customers: ', CAST(total_customers AS STRING),
           ' | sky_quantity: ' ,CAST(sku_qty AS STRING)


          -- ' | target_revenue_per_level_2: ', CAST(target_revenue_per_level_2 AS STRING),
          -- ' | weekly_sales_revenue_by_country_level_3: ', CAST(weekly_sales_revenue_by_country_level_3 AS STRING),
          -- ' | weekly_sales_revenue_by_level_1: ', CAST(weekly_sales_revenue_by_level_1 AS STRING),
          -- ' | weekly_sales_revenue_by_level_2: ', CAST(weekly_sales_revenue_by_level_2 AS STRING),
          -- ' | weekly_revenue_by_country_level_3: ', CAST(weekly_revenue_by_country_level_3 AS STRING),
          -- ' | weekly_revenue_by_level_1: ', CAST(weekly_revenue_by_level_1 AS STRING),
          -- ' | weekly_revenue_by_level_2: ', CAST(weekly_revenue_by_level_2 AS STRING),
          -- ' | weekly_units_sold_by_country_level_3: ', CAST(weekly_units_sold_by_country_level_3 AS STRING),
          -- ' | weekly_units_sold_by_level_1: ', CAST(weekly_units_sold_by_level_1 AS STRING),
          -- ' | weekly_units_sold_by_level_2: ', CAST(weekly_units_sold_by_level_2 AS STRING),
          -- ' | monthly_sales_revenue_by_country_level_3: ', CAST(monthly_sales_revenue_by_country_level_3 AS STRING),
          -- ' | monthly_sales_revenue_by_level_1: ', CAST(monthly_sales_revenue_by_level_1 AS STRING),
          -- ' | monthly_sales_revenue_by_level_2: ', CAST(monthly_sales_revenue_by_level_2 AS STRING),
          -- ' | monthly_revenue_by_country_level_3: ', CAST(monthly_revenue_by_country_level_3 AS STRING),
          -- ' | monthly_revenue_by_level_1: ', CAST(monthly_revenue_by_level_1 AS STRING),
          -- ' | monthly_revenue_by_level_2: ', CAST(monthly_revenue_by_level_2 AS STRING),
          -- ' | monthly_units_sold_by_country_level_3: ', CAST(monthly_units_sold_by_country_level_3 AS STRING),
          -- ' | monthly_units_sold_by_level_1: ', CAST(monthly_units_sold_by_level_1 AS STRING),
          -- ' | monthly_units_sold_by_level_2: ', CAST(monthly_units_sold_by_level_2 AS STRING),
          -- ' | prev_weekly_sales_revenue_country_level_3: ', CAST(prev_weekly_sales_revenue_country_level_3 AS STRING),
          -- ' | prev_weekly_revenue_country_level_3: ', CAST(prev_weekly_revenue_country_level_3 AS STRING),
          -- ' | prev_weekly_units_sold_country_level_3: ', CAST(prev_weekly_units_sold_country_level_3 AS STRING),
          -- ' | prev_weekly_sales_revenue_level_1: ', CAST(prev_weekly_sales_revenue_level_1 AS STRING),
          -- ' | prev_weekly_revenue_level_1: ', CAST(prev_weekly_revenue_level_1 AS STRING),
          -- ' | prev_weekly_units_sold_level_1: ', CAST(prev_weekly_units_sold_level_1 AS STRING),
          -- ' | prev_weekly_sales_revenue_level_2: ', CAST(prev_weekly_sales_revenue_level_2 AS STRING),
          -- ' | prev_weekly_revenue_level_2: ', CAST(prev_weekly_revenue_level_2 AS STRING),
          -- ' | prev_weekly_units_sold_level_2: ', CAST(prev_weekly_units_sold_level_2 AS STRING),
          -- ' | prev_monthly_sales_revenue_country_level_3: ', CAST(prev_monthly_sales_revenue_country_level_3 AS STRING),
          -- ' | prev_monthly_revenue_country_level_3: ', CAST(prev_monthly_revenue_country_level_3 AS STRING),
          -- ' | prev_monthly_units_sold_country_level_3: ', CAST(prev_monthly_units_sold_country_level_3 AS STRING)
        ), 
      '\n'
    ) AS full_dataset_text
  FROM 
    AggregatedMetrics
)

-- Step 3: Run the AI with strict JSON instructions to prevent NULL schema mapping
SELECT
  CURRENT_TIMESTAMP() AS analysis_generated_at,
  'month-to-date to target' AS report_type,
  ai_output.highlights,
  ai_output.lowlights,
  ai_output.executive_summary

FROM 
  DatasetSummary,
  UNNEST([
    AI.GENERATE(
      CONCAT(
        "You are a retail data analyst. Analyze this month-to-date performance dataset. ",
        "For the report type: month-to-date to target,I want you to analyse the month-to-date to target report. Identify the top highlights (where revenue beat target or spiked) and lowlights (where revenue missed target or dropped significantly). ",
        "CRITICAL: You must return your response as a valid JSON object matching the requested schema. ",
        "Format your respons in 3 bullets points", --"Do not wrap your response in markdown code blocks like ```json. Output raw JSON.\n\nData:\n"
        "Give me the text in Vietnamese using natural writing language",
        full_dataset_text
      ),
      --connection_id => 'asia-southeast1.agent_platgrom_id',
      endpoint => 'gemini-3.5-flash',
      -- Strictly structured schema fields
      output_schema => "highlights STRING, lowlights STRING, executive_summary STRING"
    )
  ]) AS ai_output


UNION ALL

SELECT
  CURRENT_TIMESTAMP() AS analysis_generated_at,
  'week-over-week' AS report_type,
  ai_output.highlights,
  ai_output.lowlights,
  ai_output.executive_summary
FROM 
  DatasetSummary,
  UNNEST([
    AI.GENERATE(
      CONCAT(
        "You are a retail data analyst. Analyze this weekly performance dataset. ",
        "For the report type: week-over-week (week starts on Monday),I want you to analyse the week-over-week report. Identify the top highlights (where revenue beat target or spiked) and lowlights (where revenue missed target or dropped significantly). ",
        "CRITICAL: You must return your response as a valid JSON object matching the requested schema. ",
        "Format your respons in 3 bullets points", --"Do not wrap your response in markdown code blocks like ```json. Output raw JSON.\n\nData:\n"
        "Give me the text in Vietnamese using natural writing language",
        full_dataset_text
      ),
      --connection_id => 'asia-southeast1.agent_platgrom_id',
      endpoint => 'gemini-3.5-flash',
      -- Strictly structured schema fields
      output_schema => "highlights STRING, lowlights STRING, executive_summary STRING"
    )
  ]) AS ai_output
)