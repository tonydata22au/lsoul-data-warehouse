CREATE TABLE FUNCTION `marine-cycle-484213-b4`.reportdb.fn_dim_sku()
AS
WITH
/* ------------------------------------------------------------------ reference
   The internal prefix dictionary — the ONLY place to edit when merchandising
   creates a new prefix.  Covers 100% of the current master (0 tree fallbacks).
   category: APP = apparel · FTW = footwear · ACC = accessories
             NON-RETAIL = packaging / gifting / uniform (excluded from OTB)     */
prefix_ref AS (
  SELECT * FROM UNNEST([
    -- ---- apparel ----------------------------------------------------------
    STRUCT('A'  AS code_prefix, 'Áo — tops'                      AS prefix_meaning, 'APP'        AS prefix_category, 'Tops'              AS prefix_sub_category),
    STRUCT('V'      , 'Váy — dresses'                   , 'APP'        , 'Dresses'           ),
    STRUCT('CV'     , 'Chân váy — skirts'               , 'APP'        , 'Skirts'            ),
    STRUCT('B'      , 'Bộ — sets / co-ords'             , 'APP'        , 'Sets / Co-ords'    ),
    STRUCT('J'      , 'Jeans — denim bottoms'           , 'APP'        , 'Denim'             ),
    STRUCT('Q'      , 'Quần dài — trousers'             , 'APP'        , 'Trousers'          ),
    STRUCT('M'      , 'Quần short — shorts'             , 'APP'        , 'Shorts'            ),
    STRUCT('K'      , 'Áo khoác — outerwear'            , 'APP'        , 'Outerwear'         ),
    STRUCT('S'      , 'Sơ mi — shirts'                  , 'APP'        , 'Shirts & Blouses'  ),
    STRUCT('L'      , 'Áo len — knitwear'               , 'APP'        , 'Knitwear'          ),
    STRUCT('OQ'     , 'Ống quần rời — detachable leg'   , 'APP'        , 'Other apparel'     ),
    -- ---- footwear ---------------------------------------------------------
    STRUCT('G'      , 'Giày — shoes & heels'            , 'FTW'        , 'Shoes'             ),
    STRUCT('Z'      , 'Boots'                           , 'FTW'        , 'Boots'             ),
    STRUCT('LJG'    , 'Giày — legacy code'              , 'FTW'        , 'Shoes'             ),
    -- ---- accessories ------------------------------------------------------
    STRUCT('TUI'    , 'Túi — bags'                      , 'ACC'        , 'Bags'              ),
    STRUCT('VI'     , 'Ví — wallets & card holders'     , 'ACC'        , 'Wallets & SLG'     ),
    STRUCT('VO'     , 'Vớ — socks'                      , 'ACC'        , 'Socks'             ),
    STRUCT('SG'     , 'Sunglasses'                      , 'ACC'        , 'Sunglasses'        ),
    STRUCT('BT'     , 'Bao tay — gloves'                , 'ACC'        , 'Gloves'            ),
    STRUCT('PK'     , 'Phụ kiện — accessories'          , 'ACC'        , 'Other accessories' ),
    STRUCT('DT'     , 'Dây chuyền — necklaces'          , 'ACC'        , 'Jewellery'         ),
    STRUCT('NH'     , 'Nhẫn — rings'                    , 'ACC'        , 'Jewellery'         ),
    STRUCT('X'      , 'Phụ kiện rời — trims & add-ons'  , 'ACC'        , 'Other accessories' ),
    -- ---- non-retail -------------------------------------------------------
    STRUCT('HQ'     , 'Hộp quà / hộp đóng gói'          , 'NON-RETAIL' , 'Packaging'         ),
    STRUCT('HHT'    , 'Hộp trắng'                       , 'NON-RETAIL' , 'Packaging'         ),
    STRUCT('HTG'    , 'Hộp trắng nhỏ / hộp giày'        , 'NON-RETAIL' , 'Packaging'         ),
    STRUCT('HNQA'   , 'Hộp nâu quần áo'                 , 'NON-RETAIL' , 'Packaging'         ),
    STRUCT('TDG'    , 'Túi giấy — giày'                 , 'NON-RETAIL' , 'Packaging'         ),
    STRUCT('TGN'    , 'Túi giấy — nhỏ'                  , 'NON-RETAIL' , 'Packaging'         ),
    STRUCT('TGL'    , 'Túi giấy — lớn'                  , 'NON-RETAIL' , 'Packaging'         ),
    STRUCT('HT'     , 'Hàng tặng — giveaway'            , 'NON-RETAIL' , 'Gifting'           ),
    STRUCT('DOIHANG', 'Đổi hàng — exchange placeholder' , 'NON-RETAIL' , 'Internal'          )
  ])
)

/* -------------------------------------------------------------- product master
   One row per variation_code. core_variations already carries size and colour
   as columns — no need to re-parse variation_attributes.                      */
,sku_master AS (
  SELECT
     UPPER(TRIM(v.variation_display_id))                    AS variation_code
    ,ANY_VALUE(UPPER(TRIM(v.product_code)))                 AS product_code
    ,ANY_VALUE(p.product_name)                              AS product_name
    ,ANY_VALUE(variation_attributes)                        AS product_attributes
    ,ANY_VALUE(p.product_launch_date)                       AS product_launch_date
    ,ANY_VALUE(NULLIF(UPPER(TRIM(v.size_value )), ''))      AS size_label
    ,ANY_VALUE(NULLIF(UPPER(TRIM(v.color_value)), ''))      AS color_label
    ,ANY_VALUE(v.retail_price)                              AS retail_price
    ,MAX(v.remain_quantity)                                 AS remain_quantity
    ,MAX(IFNULL(v.is_removed,0))                            AS is_removed
    ,MAX(IFNULL(v.is_hidden ,0))                            AS is_hidden
    ,MAX(CASE WHEN UPPER(IFNULL(p.product_tags,'')) LIKE '%SYS_01_SALE_END%' THEN 1 ELSE 0 END) AS is_sale_end
  FROM `marine-cycle-484213-b4.core_pancake.core_variations` v
  JOIN `marine-cycle-484213-b4.core_pancake.core_product`    p
    ON v.product_id = p.raw_product_id
  GROUP BY variation_code
)

/* ------------------------------------------------------------- legacy tree (QA)
   Kept to (a) fall back on unknown prefixes and (b) produce a fix-at-source
   list. Do NOT classify from it: its level-2 labels are stale.                */
,tree AS (
  SELECT
     UPPER(TRIM(string_field_1))  AS variation_code
    ,UPPER(TRIM(string_field_4))  AS tree_cat_l1
    ,UPPER(TRIM(string_field_3))  AS tree_cat_l2
    ,UPPER(TRIM(string_field_5))  AS tree_collection_bst
  FROM `marine-cycle-484213-b4.reportdb.product_tree_20260824`
  WHERE string_field_1 IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(string_field_1))
                             ORDER BY string_field_4, string_field_3) = 1
)

/* ------------------------------------------------------------ parse the code */
,parsed AS (
  SELECT
     m.*
    ,t.tree_cat_l1
    ,t.tree_cat_l2
    ,t.tree_collection_bst
    ,REGEXP_EXTRACT(m.product_code, r'^([A-Z]+)')         AS code_prefix
    ,REGEXP_EXTRACT(m.product_code, r'^[A-Z]+([0-9]+)$')  AS code_digits
    ,SAFE_CAST(REGEXP_EXTRACT(m.variation_code, r'-([0-9]+)$') AS INT64) AS variant_no
     -- Name normalised for matching: accents stripped, WORD BREAKS KEPT.
     -- Deliberately NOT sysdb.udf_remove_vn_accents() — see header note (a).
    ,TRIM(REGEXP_REPLACE(
        UPPER(REGEXP_REPLACE(
          NORMALIZE(TRANSLATE(IFNULL(m.product_name,''), 'ĐđƠơƯư', 'DdOoUu'), NFD),
          r'\pM+', '')),
        r'[^A-Z0-9]+', ' '))                              AS name_norm
  FROM sku_master m
  LEFT JOIN tree t USING (variation_code)
)

/* ------------------------------------------------- code vintage & size/colour */
,attrs AS (
  SELECT
     p.*
    ,r.prefix_meaning
    ,r.prefix_category
    ,r.prefix_sub_category
     -- only codes carrying YYMM + a 4-digit sequence have a vintage
    ,IF(LENGTH(code_digits) >= 8,
        SAFE.PARSE_DATE('%y%m', SUBSTR(code_digits,1,4)), NULL)              AS code_created_ym
    ,IF(LENGTH(code_digits) >= 8,
        SAFE_CAST(SUBSTR(code_digits,5) AS INT64),
        SAFE_CAST(code_digits AS INT64))                                     AS style_seq
    ,LENGTH(IFNULL(code_digits,'')) < 8                                      AS is_legacy_code
     -- fabric cross-cuts silhouette: a denim SKIRT stays in Skirts
    ,REGEXP_CONTAINS(name_norm, r'\b(JEAN|JEANS|DENIM)\b')                   AS is_denim
    ,CASE
       WHEN size_label IS NULL                                     THEN 'N/A'
       WHEN REGEXP_CONTAINS(size_label, r'^[0-9]{2}$')             THEN 'NUMERIC'    -- footwear
       WHEN size_label IN ('XS','S','M','L','XL','XXL','SMALL','MEDIUM','LARGE') THEN 'ALPHA'
       WHEN REGEXP_CONTAINS(size_label, r'FREE ?SIZE|ONE ?SIZE')   THEN 'ONE SIZE'
       ELSE 'OTHER'
     END                                                                     AS size_type
    ,CASE size_label
       WHEN 'XS' THEN 1 WHEN 'S' THEN 2 WHEN 'SMALL'  THEN 2
       WHEN 'M'  THEN 3 WHEN 'MEDIUM' THEN 3
       WHEN 'L'  THEN 4 WHEN 'LARGE'  THEN 4
       WHEN 'XL' THEN 5 WHEN 'XXL'    THEN 6
       ELSE COALESCE(SAFE_CAST(size_label AS INT64), 99)   -- 99 = freesize / n.a.
     END                                                                     AS size_order
  FROM parsed p
  LEFT JOIN prefix_ref r ON r.code_prefix = p.code_prefix
)

/* ----------------------------------------------------------------- classify
   One flat CASE, first match wins. Name rules are always scoped to a prefix
   family, so a name token can refine a bucket but can never move a SKU into
   another department by accident.                                            */
,classified AS (
  SELECT
     a.*
    ,CASE
       -- 1. out-of-family overrides: never part of a customer OTB buy --------
       WHEN REGEXP_CONTAINS(name_norm, r'\bDONG PHUC\b')
            THEN STRUCT('NON-RETAIL' AS category, 'Staff uniform' AS sub_category, 'NAME_OVERRIDE' AS classification_source)
       WHEN REGEXP_CONTAINS(name_norm, r'\b(HANG TANG|QUA TANG)\b')
            THEN STRUCT('NON-RETAIL','Gifting'          ,'NAME_OVERRIDE')
       WHEN code_prefix = 'HT' AND REGEXP_CONTAINS(name_norm, r'\bHOA TAI\b')
            THEN STRUCT('ACC'       ,'Jewellery'        ,'NAME_OVERRIDE')
       WHEN code_prefix = 'L'  AND REGEXP_CONTAINS(name_norm, r'\b(KHAN|SCARF)\b')
            THEN STRUCT('ACC'       ,'Scarves'          ,'NAME_OVERRIDE')

       -- 2. footwear: G and Z both hold every silhouette, so the name decides -
       WHEN prefix_category = 'FTW' AND REGEXP_CONTAINS(name_norm, r'\bBOOTS?\b')                        THEN STRUCT('FTW','Boots'             ,'PREFIX+NAME')
       WHEN prefix_category = 'FTW' AND REGEXP_CONTAINS(name_norm, r'\b(HEEL|HEELS|CAO GOT)\b')          THEN STRUCT('FTW','Heels'             ,'PREFIX+NAME')
       WHEN prefix_category = 'FTW' AND REGEXP_CONTAINS(name_norm, r'\b(SNEAKERS?|THE THAO)\b')          THEN STRUCT('FTW','Sneakers'          ,'PREFIX+NAME')
       WHEN prefix_category = 'FTW' AND REGEXP_CONTAINS(name_norm, r'\b(BALLERINAS?|BUP BE|FLATS?)\b')   THEN STRUCT('FTW','Flats & Ballerinas','PREFIX+NAME')
       WHEN prefix_category = 'FTW' AND REGEXP_CONTAINS(name_norm, r'\b(SANDALS?|DEP|MULES?|SLIDES?)\b') THEN STRUCT('FTW','Sandals & Slides'  ,'PREFIX+NAME')
       WHEN prefix_category = 'FTW' AND REGEXP_CONTAINS(name_norm, r'\bLOAFERS?\b')                      THEN STRUCT('FTW','Loafers'           ,'PREFIX+NAME')

       -- 3. apparel: compound garments before the generic noun ---------------
       WHEN code_prefix IN ('A','S','L','V') AND REGEXP_CONTAINS(name_norm, r'\bBODYSUITS?\b')                  THEN STRUCT('APP','Bodysuits'       ,'PREFIX+NAME')
       WHEN code_prefix IN ('A','S','L','V') AND REGEXP_CONTAINS(name_norm, r'\b(JUMPSUITS?|JUMP|PLAYSUITS?)\b')THEN STRUCT('APP','Jumpsuits'       ,'PREFIX+NAME')
       WHEN code_prefix IN ('A','S','L','V') AND REGEXP_CONTAINS(name_norm, r'\b(BRA|BIKINI|SWIM|LINGERIE)\b')  THEN STRUCT('APP','Lingerie & Swim' ,'PREFIX+NAME')
       WHEN code_prefix IN ('A','S','L','K') AND REGEXP_CONTAINS(name_norm, r'\b(LEN|KNIT|CARDIGAN|SWEATER)\b') THEN STRUCT('APP','Knitwear'        ,'PREFIX+NAME')
       WHEN code_prefix IN ('A','S','L')     AND REGEXP_CONTAINS(name_norm, r'\b(SO MI|SOMI|SHIRT|BLOUSE)\b')   THEN STRUCT('APP','Shirts & Blouses','PREFIX+NAME')
       -- J is the denim department but ~25% of it is woven trousers
       WHEN code_prefix = 'J' AND NOT REGEXP_CONTAINS(name_norm, r'\b(JEAN|JEANS|DENIM)\b')                     THEN STRUCT('APP','Trousers'        ,'PREFIX+NAME')

       -- 4. accessories: split the catch-all prefixes ------------------------
       WHEN code_prefix = 'PK' AND REGEXP_CONTAINS(name_norm, r'\b(KHAN|SCARF)\b')                              THEN STRUCT('ACC','Scarves'         ,'PREFIX+NAME')
       WHEN code_prefix = 'PK' AND REGEXP_CONTAINS(name_norm, r'\b(BOW|NO|HEADBAND|CAI TOC|BANDEAU)\b')         THEN STRUCT('ACC','Hair & Bows'     ,'PREFIX+NAME')
       WHEN code_prefix = 'X'  AND REGEXP_CONTAINS(name_norm, r'\b(BAO TAY|GLOVES?)\b')                         THEN STRUCT('ACC','Gloves'          ,'PREFIX+NAME')

       -- 5. the prefix dictionary — the normal path --------------------------
       WHEN prefix_category IS NOT NULL
            THEN STRUCT(prefix_category, prefix_sub_category, 'PREFIX')

       -- 6. fallback: legacy tree (currently fires on 0 rows) ----------------
       WHEN tree_cat_l1 IN ('HỘP','TÚI GIẤY','QUÀ','ĐỒNG PHỤC')                                  THEN STRUCT('NON-RETAIL','Packaging'        ,'TREE')
       WHEN tree_cat_l1 = 'SHOES' OR tree_cat_l2 = 'SHOES'                                       THEN STRUCT('FTW'       ,'Shoes'            ,'TREE')
       WHEN tree_cat_l1 IN ('TÚI','VI','VỚ','KÍNH','KHĂN CHOÀNG','PHỤ KIỆN')
            OR tree_cat_l2 = 'PHỤ KIỆN'                                                          THEN STRUCT('ACC'       ,'Other accessories','TREE')
       WHEN tree_cat_l1 = 'CLOTHING'                                                             THEN STRUCT('APP'       ,'Other apparel'    ,'TREE')

       -- 7. give up, but say why ---------------------------------------------
       ELSE STRUCT('UNMAPPED','Unknown code prefix','UNMAPPED')
     END AS cls
  FROM attrs a
)

SELECT
   -- identity ----------------------------------------------------------------
   variation_code
  ,product_code
  ,variant_no
  ,product_name
  ,name_norm                                                     -- matching key
   -- classification ----------------------------------------------------------
  ,cls.category                    AS category            -- APP/FTW/ACC/NON-RETAIL/UNMAPPED
  ,cls.sub_category                AS sub_category
  ,cls.classification_source       AS classification_source -- PREFIX / PREFIX+NAME / NAME_OVERRIDE / TREE / UNMAPPED
  ,tree_collection_bst             AS collection_bst
  ,code_prefix
  ,prefix_meaning
  ,is_denim
   -- code vintage (ageing / FIFO / "when was this style born") ---------------
  ,code_created_ym                                               -- 2507 -> 2025-07-01
  ,FORMAT_DATE('%Y-%m', code_created_ym)                          AS code_vintage
  ,EXTRACT(YEAR  FROM code_created_ym)                            AS code_year
  ,EXTRACT(MONTH FROM code_created_ym)                            AS code_month
  ,CONCAT(CAST(EXTRACT(YEAR FROM code_created_ym) AS STRING),
          IF(EXTRACT(MONTH FROM code_created_ym) <= 6, '-H1', '-H2')) AS code_half
  ,DATE_DIFF(CURRENT_DATE('Asia/Ho_Chi_Minh'), code_created_ym, MONTH) AS code_age_months
  ,style_seq
  ,is_legacy_code
  ,product_launch_date
   -- variant attributes ------------------------------------------------------
  ,product_attributes
  ,size_label
  ,size_type
  ,size_order
  ,color_label
  ,retail_price
  ,remain_quantity
  ,is_sale_end
  ,is_removed
  ,is_hidden
   -- QA: what the legacy tree says, and where it disagrees -------------------
  ,tree_cat_l1
  ,tree_cat_l2
  ,(tree_cat_l1 IS NOT NULL
    AND cls.classification_source LIKE 'PREFIX%'
    AND CASE
          WHEN cls.category = 'FTW' THEN NOT (tree_cat_l1 = 'SHOES' OR tree_cat_l2 = 'SHOES')
          WHEN cls.category = 'APP' THEN tree_cat_l1 <> 'CLOTHING'
          WHEN cls.category = 'ACC' THEN tree_cat_l1 NOT IN ('TÚI','VI','VỚ','KÍNH','KHĂN CHOÀNG','PHỤ KIỆN')
          ELSE FALSE
        END)                       AS tree_conflict
FROM classified
ORDER BY category, sub_category, product_code;
