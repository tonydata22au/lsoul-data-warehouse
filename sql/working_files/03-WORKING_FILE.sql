/* =============================================================================
   LSOUL DASHBOARD -- PHASE 2b: SPECIFIC ACTIONS + FULL BILINGUAL STRUCTURE
   Run AFTER Phase 2. This file is the SOLE owner of dash_action_items.

   WHY THIS FILE EXISTS
   The first cut of dash_action_items produced generic directives ("Check traffic",
   "Check discount depth and product mix"). Those are not operational. This file
   adds a specificity layer so every action names a concrete target - a specific
   store and trading window, a specific platform, or a specific SKU - with the
   numbers that justify it.

   WHAT CAN AND CANNOT BE MADE SPECIFIC (checked against the data, not assumed)
     AVAILABLE, so actions use it:
       - level_3 attribution: which store / platform inside a channel moved
       - trading-window attribution: order_date carries real time-of-day
       - required run-rate to close an MTD gap, and the step-up multiple
       - SKU-level cover, sell-through, units and tied-up value
     NOT AVAILABLE, so actions never claim it:
       - DISCOUNT DEPTH. gross (sales_revenue) vs net (revenue) differs by only
         0.0-5.7% and that gap is platform fees/vouchers, not item discount.
         Item discount is already inside sales_revenue and is not separable.
         An action like "cut discount from 20% to 12%" would be fabricated, so
         discount-depth directives are NOT generated. To enable them, the source
         needs an item-level list-price vs sold-price field.
       - TRAFFIC / FOOTFALL / SESSIONS. Absent from every source. Conversion-rate
         directives are therefore not generated; instead the traffic gap is
         raised as its own owner-tagged action.
       - STAFF ROSTERS. Not in BigQuery. Actions name the WINDOW to review, and
         leave roster detail to the owner who holds it.

   Creates:
     1. dash_store_hour_wow    -- trading-window attribution for offline stores
     2. dash_action_context    -- one row per channel: the specific anchor + numbers
     3. dash_action_items      -- REPLACES the generic version
     4. v_dash_trend_page1/2   -- section 2, bilingual labels
     5. v_dash_stock_lists_bi  -- section 3, bilingual labels
   ============================================================================= */


/* -----------------------------------------------------------------------------
   1. dash_store_hour_wow
   -----------------------------------------------------------------------------
   order_date is a DATETIME with real time-of-day (726 distinct times in 796 rows
   on a sample week), so a store's move can be localised to a trading window.
   Offline stores only - a "review this window" directive is a store-ops action.

   Live example (Store Nguyễn Trãi, Aug 3-9 vs Jul 27-Aug 2):
       12:00-13:59  bills 40->28, basket 7,217->3,970 kVND, -178m  <- worst window
       14:00-17:59  bills 129->126 (flat), basket 4,943->4,047 kVND, -128m
       18:00-20:59  +89m
   Two different problems in one store, four hours apart. A channel-level number
   cannot see that.
   ----------------------------------------------------------------------------- */
DROP TABLE IF EXISTS `marine-cycle-484213-b4.reportdb.dash_store_hour_wow`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_store_hour_wow` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),
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


/* -----------------------------------------------------------------------------
   2. dash_action_context
   -----------------------------------------------------------------------------
   One row per channel that appears in dash_highlights, carrying the SPECIFIC
   anchor an action should name. All arithmetic here, none in the model.
   ----------------------------------------------------------------------------- */
DROP TABLE IF EXISTS `marine-cycle-484213-b4.reportdb.dash_action_context`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_action_context` AS
WITH p AS (SELECT * FROM `marine-cycle-484213-b4.reportdb.dash_run_params`),

-- (a) which level_3 inside the channel drove the move
l3 AS (
  SELECT b.country, b.level_2, b.level_3,
    SUM(IF(b.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, b.nmv,0))
  - SUM(IF(b.period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, b.nmv,0)) AS delta_nmv,
    COUNT(DISTINCT IF(b.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, b.order_id,NULL)) AS bills_cur,
    COUNT(DISTINCT IF(b.period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, b.order_id,NULL)) AS bills_prv,
    SAFE_DIVIDE(SUM(IF(b.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, b.nmv,0)),
      NULLIF(COUNT(DISTINCT IF(b.period_date BETWEEN p.cur_wk_start AND p.cur_wk_end, b.order_id,NULL)),0)) AS basket_cur,
    SAFE_DIVIDE(SUM(IF(b.period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, b.nmv,0)),
      NULLIF(COUNT(DISTINCT IF(b.period_date BETWEEN p.prv_wk_start AND p.prv_wk_end, b.order_id,NULL)),0)) AS basket_prv
  FROM `marine-cycle-484213-b4.reportdb.dash_base_order_day` b CROSS JOIN p
  WHERE b.period_date BETWEEN p.prv_wk_start AND p.cur_wk_end
  GROUP BY 1,2,3
),
l3_top AS (   -- the single largest contributor, signed the same way as the channel
  SELECT * EXCEPT(rn) FROM (
    SELECT l3.*, ROW_NUMBER() OVER (PARTITION BY country, level_2 ORDER BY ABS(delta_nmv) DESC) rn
    FROM l3
  ) WHERE rn = 1
),

-- (b) worst trading window, offline stores only
win AS (
  SELECT * EXCEPT(rn) FROM (
    SELECT h.*, ROW_NUMBER() OVER (PARTITION BY country, level_2 ORDER BY delta_nmv ASC) rn
    FROM `marine-cycle-484213-b4.reportdb.dash_store_hour_wow` h
  ) WHERE rn = 1
),

-- (c) MTD run-rate maths
rr AS (
  SELECT country, level_2, data_as_of, month_start, attainment_pct, gap_to_target,
         mtd_actual_nmv, full_month_target,
         DATE_DIFF(data_as_of, month_start, DAY) + 1                AS days_done,
         DATE_DIFF(LAST_DAY(month_start), data_as_of, DAY)          AS days_left,
         SAFE_DIVIDE(mtd_actual_nmv, DATE_DIFF(data_as_of, month_start, DAY)+1) AS achieved_daily,
         SAFE_DIVIDE(full_month_target - mtd_actual_nmv,
           NULLIF(DATE_DIFF(LAST_DAY(month_start), data_as_of, DAY),0))         AS required_daily
  FROM `marine-cycle-484213-b4.reportdb.dash_page2_mtd`
)
SELECT
   h.page, h.item_type, h.rank_in_group, h.country, h.level_1, h.level_2
  ,h.impact_vnd, h.pct_change, h.driver, h.diagnosis, h.diagnosis_source
  -- specific owner role, not a generic tag
  ,CASE
     WHEN h.level_1 = 'Store'          THEN CONCAT(CASE h.country WHEN 'VIETNAM' THEN 'VN' WHEN 'THAILAND' THEN 'TH' ELSE 'CN' END, ' Retail Ops Manager')
     WHEN h.level_1 = 'Sale Ecommerce' THEN CONCAT(CASE h.country WHEN 'VIETNAM' THEN 'VN' WHEN 'THAILAND' THEN 'TH' ELSE 'CN' END, ' Ecom Lead')
     WHEN h.level_1 = 'Sale Online'    THEN CONCAT(CASE h.country WHEN 'VIETNAM' THEN 'VN' WHEN 'THAILAND' THEN 'TH' ELSE 'CN' END, ' Online Channel Lead')
     WHEN h.level_1 = 'Wholesales'     THEN 'VN Wholesale Manager'
     ELSE 'Commercial Planning Lead'
   END                                                    AS owner
  ,t.level_3        AS driver_level_3
  ,t.delta_nmv      AS driver_level_3_delta
  ,t.bills_prv      AS driver_l3_bills_prv
  ,t.bills_cur      AS driver_l3_bills_cur
  ,t.basket_prv     AS driver_l3_basket_prv
  ,t.basket_cur     AS driver_l3_basket_cur
  ,w.trading_window AS worst_window
  ,w.delta_nmv      AS worst_window_delta
  ,w.bills_prv      AS window_bills_prv
  ,w.bills_cur      AS window_bills_cur
  ,w.basket_prv     AS window_basket_prv
  ,w.basket_cur     AS window_basket_cur
  ,r.days_left, r.achieved_daily, r.required_daily
  ,SAFE_DIVIDE(r.required_daily, NULLIF(r.achieved_daily,0)) AS stepup_x
FROM `marine-cycle-484213-b4.reportdb.dash_highlights` h
LEFT JOIN l3_top t ON t.country = h.country AND t.level_2 = h.level_2
LEFT JOIN win    w ON w.country = h.country AND w.level_2 = h.level_2
LEFT JOIN rr     r ON r.country = h.country AND r.level_2 = h.level_2;


/* -----------------------------------------------------------------------------
   3. dash_action_items   -- REPLACES the generic version
   -----------------------------------------------------------------------------
   section = 'PERFORMANCE' : traces to a named highlight/lowlight. Max 5 per page.
   section = 'STOCK'       : traces to a named SKU list. Max 5, shown on both pages.

   The English text is built here in SQL, so it is deterministic and survives a
   model outage. The AI layer rewrites it into polished EN and natural business
   Vietnamese - it never changes a number or invents a target.
   ----------------------------------------------------------------------------- */
DROP TABLE IF EXISTS `marine-cycle-484213-b4.reportdb.dash_action_items`;
CREATE OR REPLACE TABLE `marine-cycle-484213-b4.reportdb.dash_action_items` AS
WITH perf AS (
  SELECT
     c.page
    ,'PERFORMANCE' AS section
    ,c.owner
    ,CONCAT(c.country, ' / ', c.level_2, ' ',
            IF(c.item_type='HIGHLIGHT','HIGHLIGHT','LOWLIGHT')) AS source_item
    ,c.impact_vnd
    ,c.item_type
    ,ABS(c.impact_vnd) AS sort_key
    ,CASE
       ------------------------------------------------------------------ PAGE 1
       -- Offline store decline that concentrates in one trading window
       WHEN c.page='PAGE1_WOW' AND c.item_type='LOWLIGHT' AND c.level_1='Store'
            AND c.worst_window IS NOT NULL THEN
         FORMAT('Review floor coverage and merchandising at %s during the %s window, where bills moved %d->%d and basket moved %s->%s kVND (%s mVND, the largest single loss window this week)',
           IFNULL(c.driver_level_3, c.level_2), c.worst_window,
           c.window_bills_prv, c.window_bills_cur,
           FORMAT('%.0f', c.window_basket_prv/1e3), FORMAT('%.0f', c.window_basket_cur/1e3),
           FORMAT('%.0f', c.worst_window_delta/1e6))
       -- Wholesale: order count is the lever, not price
       WHEN c.page='PAGE1_WOW' AND c.item_type='LOWLIGHT' AND c.level_1='Wholesales' THEN
         FORMAT('Re-contact the lapsed wholesale accounts: order count fell %d->%d (%s mVND) even though average order value rose %s->%s kVND',
           c.driver_l3_bills_prv, c.driver_l3_bills_cur, FORMAT('%.0f', c.impact_vnd/1e6),
           FORMAT('%.0f', c.driver_l3_basket_prv/1e3), FORMAT('%.0f', c.driver_l3_basket_cur/1e3))
       -- Any other decline: name the platform/store that caused it
       WHEN c.page='PAGE1_WOW' AND c.item_type='LOWLIGHT' THEN
         FORMAT('Investigate %s specifically, which accounts for %s mVND of the %s mVND channel decline (bills %d->%d, basket %s->%s kVND)',
           IFNULL(c.driver_level_3,'the largest sub-channel'),
           FORMAT('%.0f', c.driver_level_3_delta/1e6), FORMAT('%.0f', c.impact_vnd/1e6),
           c.driver_l3_bills_prv, c.driver_l3_bills_cur,
           FORMAT('%.0f', c.driver_l3_basket_prv/1e3), FORMAT('%.0f', c.driver_l3_basket_cur/1e3))
       -- Growth: protect the specific platform that delivered it
       WHEN c.page='PAGE1_WOW' AND c.item_type='HIGHLIGHT' THEN
         FORMAT('Hold stock cover and fulfilment capacity on %s, which delivered %s mVND of the %s mVND channel gain on bills %d->%d - confirm it survives past the promo window',
           IFNULL(c.driver_level_3,'the lead sub-channel'),
           FORMAT('%.0f', c.driver_level_3_delta/1e6), FORMAT('%.0f', c.impact_vnd/1e6),
           c.driver_l3_bills_prv, c.driver_l3_bills_cur)
       ------------------------------------------------------------------ PAGE 2
       -- Gap too large to trade out of -> re-forecast, do not "push harder"
       WHEN c.page='PAGE2_MTD' AND c.item_type='LOWLIGHT' AND c.stepup_x >= 2.5 THEN
         FORMAT('Re-forecast the month: closing the %s mVND gap needs %s mVND/day for the remaining %d days versus %s mVND/day achieved, a %sx step-up that is unlikely to be traded out - escalate a revised number rather than a push',
           FORMAT('%.0f', c.impact_vnd/1e6), FORMAT('%.0f', c.required_daily/1e6),
           c.days_left, FORMAT('%.0f', c.achieved_daily/1e6), FORMAT('%.1f', c.stepup_x))
       WHEN c.page='PAGE2_MTD' AND c.item_type='LOWLIGHT' THEN
         FORMAT('Build a recovery plan to lift daily run-rate from %s to %s mVND for the remaining %d days (%sx step-up) and close the %s mVND gap',
           FORMAT('%.0f', c.achieved_daily/1e6), FORMAT('%.0f', c.required_daily/1e6),
           c.days_left, FORMAT('%.1f', c.stepup_x), FORMAT('%.0f', c.impact_vnd/1e6))
       WHEN c.page='PAGE2_MTD' AND c.item_type='HIGHLIGHT' THEN
         FORMAT('Protect the run-rate: %s mVND/day achieved versus %s mVND/day still required, so reallocate promo and stock support toward the channels behind plan rather than adding spend here',
           FORMAT('%.0f', c.achieved_daily/1e6), FORMAT('%.0f', c.required_daily/1e6))
       ELSE NULL
     END AS action_text
  FROM `marine-cycle-484213-b4.reportdb.dash_action_context` c
),
-- Traffic gap raised as its own action wherever bills fell. Required by the brief:
-- traffic is unavailable, so flag it as the first thing to check rather than skip it.
traffic AS (
  SELECT
     w.page, 'PERFORMANCE' AS section, 'Data / BI Lead' AS owner
    ,CONCAT(w.country, ' / ', w.level_2, ' LOWLIGHT') AS source_item
    ,w.impact_vnd, w.item_type, ABS(w.impact_vnd) * 0.5 AS sort_key
    ,FORMAT('Instrument traffic capture for %s / %s before the next cycle: bills fell %s%% but no footfall or session data is collected in any source system, so a traffic loss and a conversion loss cannot currently be told apart',
       w.country, w.level_2, FORMAT('%.0f', w.pct_bills*100)) AS action_text
  FROM `marine-cycle-484213-b4.reportdb.dash_highlights` w
  WHERE w.page='PAGE1_WOW' AND w.item_type='LOWLIGHT' AND w.pct_bills < -0.03
),
-- Stock actions, anchored on named SKUs.
stock AS (
  SELECT 'BOTH' AS page, 'STOCK' AS section, 'Merchandising Planner' AS owner,
         CONCAT('Stock list: ', list_name) AS source_item,
         rank_value AS impact_vnd, 'LOWLIGHT' AS item_type, rank_value AS sort_key,
         CASE list_name
           WHEN 'OVERSTOCK' THEN FORMAT('Put %s (%s) into a clearance or transfer plan: %d units on hand, %s weeks of cover, %s%% sell-through and %s mVND of value tied up',
             variation_code, IFNULL(product_name,'unnamed'), CAST(units_on_hand AS INT64),
             FORMAT('%.0f', cover_weeks), FORMAT('%.0f', sell_through_rate*100), FORMAT('%.0f', rank_value/1e6))
           WHEN 'UNDERSTOCK' THEN FORMAT('Raise a replenishment order for %s (%s) now: only %d units left at %s weeks cover with %s%% sell-through, putting %s mVND of four-week demand at risk',
             variation_code, IFNULL(product_name,'unnamed'), CAST(units_on_hand AS INT64),
             FORMAT('%.1f', cover_weeks), FORMAT('%.0f', sell_through_rate*100), FORMAT('%.0f', rank_value/1e6))
           WHEN 'DISCONTINUED' THEN FORMAT('Clear discontinued %s (%s): %d units still held at %s mVND retail value with %s%% sell-through and no active sales plan',
             variation_code, IFNULL(product_name,'unnamed'), CAST(units_on_hand AS INT64),
             FORMAT('%.0f', rank_value/1e6), FORMAT('%.0f', sell_through_rate*100))
           ELSE FORMAT('Secure supply for trending %s (%s): units sold rose %d->%d week on week with %s weeks of cover remaining',
             variation_code, IFNULL(product_name,'unnamed'),
             CAST(IFNULL(units_prv,0) AS INT64), CAST(IFNULL(units_cur,0) AS INT64), FORMAT('%.1f', cover_weeks))
         END AS action_text
  FROM `marine-cycle-484213-b4.reportdb.dash_stock_lists`
  WHERE rank_in_list <= 2
),
u AS (
  SELECT page, section, owner, source_item, impact_vnd, item_type, sort_key, action_text FROM perf
  WHERE action_text IS NOT NULL
  UNION ALL SELECT page, section, owner, source_item, impact_vnd, item_type, sort_key, action_text FROM traffic
  UNION ALL SELECT page, section, owner, source_item, impact_vnd, item_type, sort_key, action_text FROM stock
)
SELECT * EXCEPT(rn, sort_key), rn AS action_no,
       CONCAT('[', owner, '] - ', action_text) AS action_item
FROM (
  SELECT u.*, ROW_NUMBER() OVER (PARTITION BY page, section ORDER BY sort_key DESC) AS rn
  FROM u
)
WHERE rn <= 5;


/* -----------------------------------------------------------------------------
   4. Section 2 (Trend view) -- bilingual labels
   -----------------------------------------------------------------------------
   Section 2 is a TABLE, not prose, so its Vietnamese comes from a deterministic
   mapping rather than the model. The diagnosis set is finite and closed, so the
   mapping is exhaustive - no model call, no cost, no risk of a mistranslation
   drifting between runs.
   ----------------------------------------------------------------------------- */
DROP VIEW IF EXISTS `marine-cycle-484213-b4.reportdb.v_dash_trend_page1`;
CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_dash_trend_page1` AS
SELECT
   w.country
  ,CASE w.country WHEN 'VIETNAM' THEN 'Việt Nam' WHEN 'THAILAND' THEN 'Thái Lan'
                  WHEN 'CHINA' THEN 'Trung Quốc' ELSE w.country END AS country_vi
  ,w.level_1, w.level_2
  ,w.nmv_prv, w.nmv_cur, w.delta_nmv, w.pct_nmv
  ,w.bills_prv, w.bills_cur, w.pct_bills
  ,w.basket_prv, w.basket_cur, w.pct_basket
  ,w.driver
  ,CASE w.driver WHEN 'bills' THEN 'số lượng hóa đơn'
                 WHEN 'basket' THEN 'giá trị giỏ hàng'
                 WHEN 'mixed' THEN 'hỗn hợp' ELSE w.driver END AS driver_vi
  ,w.diagnosis
  ,CASE w.diagnosis
     WHEN 'Fewer customers'                                   THEN 'Sụt giảm lượng khách'
     WHEN 'Weak cross-sell / upsell'                          THEN 'Bán kèm/bán thêm chưa hiệu quả'
     WHEN 'Volume loss masked by mix'                         THEN 'Mất sản lượng bị che lấp bởi cơ cấu hàng'
     WHEN 'Growth is fragile - fewer, bigger baskets'         THEN 'Tăng trưởng thiếu bền vững - ít đơn hơn nhưng giá trị đơn cao hơn'
     WHEN 'Growth via discounting'                            THEN 'Tăng trưởng nhờ giảm giá'
     WHEN 'No material revenue movement'                      THEN 'Doanh thu không biến động đáng kể'
     WHEN 'Growth driven by transaction volume'               THEN 'Tăng trưởng nhờ số lượng đơn hàng'
     WHEN 'Growth driven by basket size'                      THEN 'Tăng trưởng nhờ giá trị giỏ hàng'
     WHEN 'Growth from both volume and basket - driver is mixed' THEN 'Tăng trưởng từ cả sản lượng và giá trị đơn - yếu tố hỗn hợp'
     WHEN 'Decline driven by fewer transactions'              THEN 'Sụt giảm do số lượng đơn hàng giảm'
     WHEN 'Decline driven by smaller baskets'                 THEN 'Sụt giảm do giá trị giỏ hàng giảm'
     WHEN 'Decline from both volume and basket - driver is mixed' THEN 'Sụt giảm từ cả sản lượng và giá trị đơn - yếu tố hỗn hợp'
     WHEN 'Insufficient comparison data'                      THEN 'Không đủ dữ liệu so sánh'
     ELSE w.diagnosis END AS diagnosis_vi
  ,w.diagnosis_source
  ,w.traffic_note
  ,IF(w.traffic_note IS NULL, NULL,
     'Không có dữ liệu lưu lượng khách/traffic trong nguồn - chưa thể tách biệt sụt giảm lượng khách và sụt giảm tỷ lệ chuyển đổi. Cần kiểm tra traffic trước tiên.') AS traffic_note_vi
FROM `marine-cycle-484213-b4.reportdb.dash_page1_wow` w;

DROP VIEW IF EXISTS `marine-cycle-484213-b4.reportdb.v_dash_trend_page2`;
CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_dash_trend_page2` AS
SELECT
   m.month_start, m.data_as_of, m.mtd_days_elapsed, m.month_total_days
  ,m.country
  ,CASE m.country WHEN 'VIETNAM' THEN 'Việt Nam' WHEN 'THAILAND' THEN 'Thái Lan'
                  WHEN 'CHINA' THEN 'Trung Quốc' ELSE m.country END AS country_vi
  ,m.level_1, m.level_2
  ,m.mtd_actual_nmv, m.mtd_target, m.gap_to_target, m.attainment_pct
  ,m.mtd_bills, m.mtd_basket, m.full_month_target
  ,m.target_status
  ,CASE m.target_status WHEN 'HIT' THEN 'ĐẠT' WHEN 'MISS' THEN 'CHƯA ĐẠT' ELSE NULL END AS target_status_vi
  ,m.attainment_note
  ,CASE
     WHEN m.is_target_invalid     THEN 'Chỉ tiêu <= 0 - không tính được tỷ lệ hoàn thành'
     WHEN m.is_low_target         THEN 'Chỉ tiêu cả tháng < 500 triệu VND - đã ẩn tỷ lệ hoàn thành'
     WHEN m.is_unmapped_channel   THEN 'Có chỉ tiêu nhưng không có kênh thực tế tương ứng'
     ELSE NULL END AS attainment_note_vi
  ,m.is_low_target, m.is_target_invalid, m.is_unmapped_channel
  ,m.period_note
  ,CONCAT('Ngày ', CAST(m.mtd_days_elapsed AS STRING), '/', CAST(m.month_total_days AS STRING),
          ' - tháng chưa kết thúc') AS period_note_vi
FROM `marine-cycle-484213-b4.reportdb.dash_page2_mtd` m;


/* -----------------------------------------------------------------------------
   5. Section 3 (Stock status) -- bilingual labels
   ----------------------------------------------------------------------------- */
DROP VIEW IF EXISTS `marine-cycle-484213-b4.reportdb.v_dash_stock_lists_bi`;
CREATE OR REPLACE VIEW `marine-cycle-484213-b4.reportdb.v_dash_stock_lists_bi` AS
SELECT
   s.list_name
  ,CASE s.list_name
     WHEN 'OVERSTOCK'    THEN 'Tồn kho cao / luân chuyển chậm'
     WHEN 'UNDERSTOCK'   THEN 'Thiếu hàng / bán chạy'
     WHEN 'TRENDING'     THEN 'Sản phẩm tăng trưởng nổi bật'
     WHEN 'DISCONTINUED' THEN 'Hàng ngừng kinh doanh còn tồn'
     ELSE s.list_name END AS list_name_vi
  ,s.rank_in_list, s.variation_code, s.product_name, s.updated_date
  ,s.units_on_hand, s.cover_days, s.cover_weeks
  ,s.sell_through_rate, s.sale_velocity
  ,s.rank_value, s.rank_metric
  ,CASE s.rank_metric
     WHEN 'Tied-up excess value (VND)' THEN 'Giá trị tồn dư đang bị giam (VND)'
     WHEN 'Lost-sales risk: 4wk demand at current velocity (VND)' THEN 'Rủi ro mất doanh thu: nhu cầu 4 tuần theo tốc độ bán hiện tại (VND)'
     WHEN 'Absolute WoW unit gain (base >= 5 units)' THEN 'Mức tăng tuyệt đối số lượng bán theo tuần (nền >= 5 sản phẩm)'
     WHEN 'Stock value at retail (VND)' THEN 'Giá trị tồn kho theo giá bán lẻ (VND)'
     ELSE s.rank_metric END AS rank_metric_vi
  ,s.colour_bucket, s.alert_code, s.units_cur, s.units_prv
FROM `marine-cycle-484213-b4.reportdb.dash_stock_lists` s;


/* =============================================================================
   VALIDATION
   ============================================================================= */

-- V1. Trading-window attribution. EXPECT the worst window per store to be named.
SELECT country, level_2, level_3, trading_window, bills_prv, bills_cur,
       ROUND(nmv_prv/1e6) AS prv_m, ROUND(nmv_cur/1e6) AS cur_m, ROUND(delta_nmv/1e6) AS delta_m,
       ROUND(basket_prv/1e3) AS basket_prv_k, ROUND(basket_cur/1e3) AS basket_cur_k
FROM `marine-cycle-484213-b4.reportdb.dash_store_hour_wow`
ORDER BY delta_nmv LIMIT 10;

-- V2. Action context. EXPECT a named driver_level_3 for every highlight/lowlight.
SELECT page, item_type, country, level_2, owner, driver_level_3,
       ROUND(driver_level_3_delta/1e6) AS l3_delta_m, worst_window,
       ROUND(required_daily/1e6) AS req_daily_m, ROUND(stepup_x,2) AS stepup_x
FROM `marine-cycle-484213-b4.reportdb.dash_action_context`
ORDER BY page, item_type, rank_in_group;

-- V3. THE KEY CHECK: are the actions actually specific?
--     EXPECT every line to name a store+window, a platform, or a SKU code.
SELECT page, section, action_no, action_item
FROM `marine-cycle-484213-b4.reportdb.dash_action_items`
ORDER BY page, section, action_no;

-- V4. Bilingual section 2. EXPECT diagnosis_vi populated for every row.
SELECT country_vi, level_2, ROUND(delta_nmv/1e6) AS delta_m, driver_vi, diagnosis_vi
FROM `marine-cycle-484213-b4.reportdb.v_dash_trend_page1`
ORDER BY ABS(delta_nmv) DESC;

-- V5. Bilingual section 3.
SELECT list_name, list_name_vi, rank_in_list, variation_code, product_name,
       ROUND(rank_value/1e6) AS rank_value_m, rank_metric_vi
FROM `marine-cycle-484213-b4.reportdb.v_dash_stock_lists_bi`
WHERE rank_in_list <= 3 ORDER BY list_name, rank_in_list;