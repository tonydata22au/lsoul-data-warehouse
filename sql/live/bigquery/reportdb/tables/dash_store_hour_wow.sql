CREATE VIEW `marine-cycle-484213-b4.reportdb.dash_store_hour_wow`
AS WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`), 
src AS (
  SELECT order_date, 'VIETNAM' AS country, 'VN Offline Store' AS level_2,
         sale_channel_details AS level_3, CAST(order_id AS STRING) AS order_id, revenue AS nmv
  FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_vn_product`(0)
  UNION ALL
  SELECT order_date, 'THAILAND', 'TL Offline Store', sale_channel_details,
         CAST(order_id AS STRING), revenue_vn
  FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_thai_product`(0)
  UNION ALL
  SELECT order_date, 'CHINA', 'TQ Offline Store', 'Store TXmall',
         CAST(order_id AS STRING), revenue_vn
  FROM `marine-cycle-484213-b4.reportdb.fn_sale_store_china_product`(0)
),
o AS (   -- collapse to order grain first so bills are exact
  SELECT DATE(s.order_date) AS d, EXTRACT(HOUR FROM s.order_date) AS hr,
         s.country, s.level_2, s.level_3, s.order_id, SUM(s.nmv) AS nmv
  FROM src s CROSS JOIN p
  WHERE DATE(s.order_date) BETWEEN p.prv_wk_start AND p.cur_wk_end
  GROUP BY 1,2,3,4,5,6
),
w AS (
  SELECT o.*, 
    CASE WHEN hr < 12 THEN 'before 12:00'
         WHEN hr < 14 THEN '12:00-13:59'
         WHEN hr < 18 THEN '14:00-17:59'
         WHEN hr < 21 THEN '18:00-20:59'
         ELSE '21:00+' END AS trading_window,
    IF(o.d BETWEEN p.cur_wk_start AND p.cur_wk_end, 'cur', 'prv') AS wk
  FROM o CROSS JOIN p
)
SELECT
   country, level_2, level_3, trading_window
  ,COUNTIF(wk='prv')                                      AS bills_prv
  ,COUNTIF(wk='cur')                                      AS bills_cur
  ,SUM(IF(wk='prv', nmv, 0))                              AS nmv_prv
  ,SUM(IF(wk='cur', nmv, 0))                              AS nmv_cur
  ,SUM(IF(wk='cur', nmv, 0)) - SUM(IF(wk='prv', nmv, 0))  AS delta_nmv
  ,SAFE_DIVIDE(SUM(IF(wk='prv',nmv,0)), NULLIF(COUNTIF(wk='prv'),0)) AS basket_prv
  ,SAFE_DIVIDE(SUM(IF(wk='cur',nmv,0)), NULLIF(COUNTIF(wk='cur'),0)) AS basket_cur
FROM w
GROUP BY country, level_2, level_3, trading_window;
