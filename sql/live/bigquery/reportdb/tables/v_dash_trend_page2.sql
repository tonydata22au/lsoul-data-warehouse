CREATE VIEW `marine-cycle-484213-b4.reportdb.v_dash_trend_page2`
AS SELECT
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
