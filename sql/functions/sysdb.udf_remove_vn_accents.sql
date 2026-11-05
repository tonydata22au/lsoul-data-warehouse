CREATE OR REPLACE FUNCTION `marine-cycle-484213-b4`.sysdb.udf_remove_vn_accents(s STRING) RETURNS STRING
AS (
(
  WITH mapping AS (
    SELECT * FROM UNNEST([
      STRUCT('à' AS accent, 'a' AS latin), STRUCT('á', 'a'), STRUCT('ạ', 'a'), STRUCT('ả', 'a'), STRUCT('ã', 'a'),
      STRUCT('â', 'a'), STRUCT('ầ', 'a'), STRUCT('ấ', 'a'), STRUCT('ậ', 'a'), STRUCT('ẩ', 'a'), STRUCT('ẫ', 'a'),
      STRUCT('ă', 'a'), STRUCT('ằ', 'a'), STRUCT('ắ', 'a'), STRUCT('ặ', 'a'), STRUCT('ẳ', 'a'), STRUCT('ẵ', 'a'),

      STRUCT('è', 'e'), STRUCT('é', 'e'), STRUCT('ẹ', 'e'), STRUCT('ẻ', 'e'), STRUCT('ẽ', 'e'),
      STRUCT('ê', 'e'), STRUCT('ề', 'e'), STRUCT('ế', 'e'), STRUCT('ệ', 'e'), STRUCT('ể', 'e'), STRUCT('ễ', 'e'),

      STRUCT('ì', 'i'), STRUCT('í', 'i'), STRUCT('ị', 'i'), STRUCT('ỉ', 'i'), STRUCT('ĩ', 'i'),

      STRUCT('ò', 'o'), STRUCT('ó', 'o'), STRUCT('ọ', 'o'), STRUCT('ỏ', 'o'), STRUCT('õ', 'o'),
      STRUCT('ô', 'o'), STRUCT('ồ', 'o'), STRUCT('ố', 'o'), STRUCT('ộ', 'o'), STRUCT('ổ', 'o'), STRUCT('ỗ', 'o'),
      STRUCT('ơ', 'o'), STRUCT('ờ', 'o'), STRUCT('ớ', 'o'), STRUCT('ợ', 'o'), STRUCT('ở', 'o'), STRUCT('ỡ', 'o'),

      STRUCT('ù', 'u'), STRUCT('ú', 'u'), STRUCT('ụ', 'u'), STRUCT('ủ', 'u'), STRUCT('ũ', 'u'),
      STRUCT('ư', 'u'), STRUCT('ừ', 'u'), STRUCT('ứ', 'u'), STRUCT('ự', 'u'), STRUCT('ử', 'u'), STRUCT('ữ', 'u'),

      STRUCT('ỳ', 'y'), STRUCT('ý', 'y'), STRUCT('ỵ', 'y'), STRUCT('ỷ', 'y'), STRUCT('ỹ', 'y'),
      STRUCT('đ', 'd'),

      STRUCT('À', 'A'), STRUCT('Á', 'A'), STRUCT('Ạ', 'A'), STRUCT('Ả', 'A'), STRUCT('Ã', 'A'),
      STRUCT('Â', 'A'), STRUCT('Ầ', 'A'), STRUCT('Ấ', 'A'), STRUCT('Ậ', 'A'), STRUCT('Ẩ', 'A'), STRUCT('Ẫ', 'A'),
      STRUCT('Ă', 'A'), STRUCT('Ằ', 'A'), STRUCT('Ắ', 'A'), STRUCT('Ặ', 'A'), STRUCT('Ẳ', 'A'), STRUCT('Ẵ', 'A'),

      STRUCT('È', 'E'), STRUCT('É', 'E'), STRUCT('Ẹ', 'E'), STRUCT('Ẻ', 'E'), STRUCT('Ẽ', 'E'),
      STRUCT('Ê', 'E'), STRUCT('Ề', 'E'), STRUCT('Ế', 'E'), STRUCT('Ệ', 'E'), STRUCT('Ể', 'E'), STRUCT('Ễ', 'E'),

      STRUCT('Ì', 'I'), STRUCT('Í', 'I'), STRUCT('Ị', 'I'), STRUCT('Ỉ', 'I'), STRUCT('Ĩ', 'I'),

      STRUCT('Ò', 'O'), STRUCT('Ó', 'O'), STRUCT('Ọ', 'O'), STRUCT('Ỏ', 'O'), STRUCT('Õ', 'O'),
      STRUCT('Ô', 'O'), STRUCT('Ồ', 'O'), STRUCT('Ố', 'O'), STRUCT('Ộ', 'O'), STRUCT('Ổ', 'O'), STRUCT('Ỗ', 'O'),
      STRUCT('Ơ', 'O'), STRUCT('Ờ', 'O'), STRUCT('Ớ', 'O'), STRUCT('Ợ', 'O'), STRUCT('Ở', 'O'), STRUCT('Ỡ', 'O'),

      STRUCT('Ù', 'U'), STRUCT('Ú', 'U'), STRUCT('Ụ', 'U'), STRUCT('Ủ', 'U'), STRUCT('Ũ', 'U'),
      STRUCT('Ư', 'U'), STRUCT('Ừ', 'U'), STRUCT('Ứ', 'U'), STRUCT('Ự', 'U'), STRUCT('Ử', 'U'), STRUCT('Ữ', 'U'),

      STRUCT('Ỳ', 'Y'), STRUCT('Ý', 'Y'), STRUCT('Ỵ', 'Y'), STRUCT('Ỷ', 'Y'), STRUCT('Ỹ', 'Y'),
      STRUCT('Đ', 'D')
    ])
  )
  SELECT
    REPLACE(
      REGEXP_REPLACE(
        TRIM(
          REGEXP_REPLACE(
            (
              SELECT STRING_AGG(IFNULL(m.latin, ch), '' ORDER BY off)
              FROM UNNEST(SPLIT(s, '')) ch WITH OFFSET off
              LEFT JOIN mapping m
                ON ch = m.accent
            ),
            r'[^A-Za-z]+',
            ' '
          )
        ),
        r'\s+',
        ' '
      ),
      ' ',
      '_'
    )
)
);
