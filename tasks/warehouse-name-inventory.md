# Canonical warehouse names: live scope inventory

Observed 2026-11-02 during continuation of thread `thr_qjwbpax4cj`. This is planning evidence, not an applied migration.

The 22 accessible datasets all use `asia-southeast1`. Discovery returned 93 routines: 59 table functions, five scalar functions and 29 procedures. There are 41 functions with explicit warehouse-name references plus one name-bearing SELECT-star wrapper. Of these 42, 37 need direct edits and five can inherit corrected names. Seven additional downstream aggregate functions bring regression coverage to 49. IAM-hidden resources are not covered.

## Per-function disposition

All objects below are in `marine-cycle-484213-b4.reportdb`. Hashes use exact returned `ddl` UTF-8 bytes, including original line endings. Maintained source paths must be resolved by CREATE object name, not guessed from filename.

| Function | Disposition | Existing pending source | Live DDL SHA-256 |
| --- | --- | --- | --- |
| `fn_ads_spend_summary` | Downstream schema / aggregate regression | `Resolve by object name during Build` | `087c779bebc487af6af0f0aea523d9093c07f76593a32e4290e8499f0f0b14b6` |
| `fn_assortment_seg_cont_by_warehouse` | Direct canonical-name update | `Resolve by object name during Build` | `d4fc02452d743f10bea20439c0cd23d61f063b21e6ecad47c457d28c3b350f3e` |
| `fn_china_product_inventory` | Direct canonical-name update | `Resolve by object name during Build` | `29fe7f84b5179671827717e7a4b9d06c2200442f61aa161849ac54669d040f28` |
| `fn_order_master` | Downstream schema / aggregate regression | `Resolve by object name during Build` | `fa64e104897f75382aab00feb34c3b392ed37bd52269fe3fd2ff2cc4d1fec458` |
| `fn_order_product_inventory_summary` | Inherit corrected names / verify lineage | `Resolve by object name during Build` | `7ce4366de17d955e92cd2e83c523e5bc5e8b13fd31c326d7dc345aefb9752c63` |
| `fn_order_product_revenue_summary` | Inherit corrected names / verify lineage | `Resolve by object name during Build` | `34faf0f2cf5303ca79ae64deda430b1cf8a15f996717af1855dba2c8eaa0dafb` |
| `fn_order_revenue_summary` | Inherit corrected names / verify lineage | `Resolve by object name during Build` | `dc4094cac626b6a9471b611f5d5f181991f97a61d0107abef997056f34f326e0` |
| `fn_order_sku_master` | Downstream schema / aggregate regression | `Resolve by object name during Build` | `5506eb4fe43d6b3bae45c51d27338ed78ec6338835a4cf44c491df7c5c29c00c` |
| `fn_order_sku_warehouse_master` | Inherit corrected names / verify lineage | `Resolve by object name during Build` | `b2f48362fe835f627f36aa53cfe146f8a8cfb1e6c718bc05440cab157ebd2320` |
| `fn_order_target_master` | Downstream schema / aggregate regression | `Resolve by object name during Build` | `9958ad363b6c07d8bf73e29bd037c20af3ba72f3ce82815c1b967d5f9fda7e8f` |
| `fn_performance_snapshot` | Downstream schema / aggregate regression | `Resolve by object name during Build` | `c5d2f2619099c5fc9b0f9048f1fae43fb29d244e90b25e144fbd1ac74bfd84f3` |
| `fn_performance_snapshot_ai_generated_v2` | Downstream schema / aggregate regression | `Resolve by object name during Build` | `5aa95f9c81e2402ead9075f9e69d92722783cde952f5e6be2d5e76136be650cf` |
| `fn_performance_snapshot_v2` | Downstream schema / aggregate regression | `Resolve by object name during Build` | `aa7dc991964ae303ce411d78f0adcfdde610c00ccc674d8d78dc19c3a854cd57` |
| `fn_product_inventory_overseas_shipment` | Direct canonical-name update | `Resolve by object name during Build` | `81f00152e152afa190d3236d5dfeeed5c37799caa1fd4b0d963dab4c32384093` |
| `fn_product_inventory_summary` | Direct canonical-name update | `Resolve by object name during Build` | `a71249265c7ed1fbafae465e8295ac283a1695630497ee55bbdf4547c584bc07` |
| `fn_product_inventory_summary_v2` | Direct canonical-name update | `Resolve by object name during Build` | `aec09ef8c70b9b80d7327cbaca1a602d2a9173e587735b458da8b1de1ff06a67` |
| `fn_product_variations_warehouse_summary` | Direct canonical-name update | `Resolve by object name during Build` | `3b933a678d97391818bdd05cd1c48c7d3c630a4875bd8a53027236885e38f99c` |
| `fn_sale_ecom_china` | Direct canonical-name update | `Resolve by object name during Build` | `02ca2bed1efc28095e2c6598ff8fadee0ca48ee2f218f1258813bc61da5c035c` |
| `fn_sale_ecom_china_product` | Direct canonical-name update | `Resolve by object name during Build` | `e9bb32e0364285fb7c2492a3c09ccc256218fa998e0ac9762ea35b1d15e88eac` |
| `fn_sale_ecom_china_v2` | Direct canonical-name update | `Resolve by object name during Build` | `2e6be9992ce1c9fdeb29f77183f61044b913da8c8bb519bbdddef850a345784c` |
| `fn_sale_ecom_taobao_tmall_manual_china` | Direct canonical-name update | `Resolve by object name during Build` | `8a7325d8642727ec3bede0825dbdff26ba3d2e61f991169ec90e1a41691574d1` |
| `fn_sale_ecom_taobao_tmall_manual_china_product` | Direct canonical-name update | `Resolve by object name during Build` | `a74d2ecfa10e7eadb11b716f22f9cbb7a10d8afe89f45434854f894029e8e584` |
| `fn_sale_ecom_taobao_tmall_manual_china_v2` | Direct canonical-name update | `Resolve by object name during Build` | `35f0990d508bd9712817230f3289957982b15f7331cd90bc7a2472df1542ea4f` |
| `fn_sale_ecom_thai` | Direct canonical-name update | `Resolve by object name during Build` | `0a4ba1a15007077022e74912419df08cb317ded69acbc21e691a6521dd520b8a` |
| `fn_sale_ecom_thai_product` | Direct canonical-name update | `Resolve by object name during Build` | `7f45216c00b5de6a0c9f50761ce6fca9851961b9451e0e4fdf5e760f72aac55a` |
| `fn_sale_ecom_thai_v2` | Direct canonical-name update | `Resolve by object name during Build` | `7a02da5f19bdebdb1dcaa662981097944c6ec825c366437237e6e3c2b2fa50b9` |
| `fn_sale_ecom_vn` | Direct canonical-name update | `sql/functions/reportdb.fn_sale_ecom_vn.sql` | `ae77397a9fee9dbdbfc6135332472ddfa77ed57263149d548ca4549e8cabbca6` |
| `fn_sale_ecom_vn_product` | Direct canonical-name update | `sql/functions/reportdb.fn_sale_ecom_vn_product.sql` | `88927513bd48654f843c41ff9f85688d087f716702e48dfe1ef7715229a57975` |
| `fn_sale_ecom_vn_v2` | Direct canonical-name update | `sql/functions/fn_sale_ecom_vn.sql` | `3e86a1a4939a7a72c0258dbbbbd5591e5261f8d53e2498acb85183786c2661f3` |
| `fn_sale_online_thai_product` | Direct canonical-name update | `Resolve by object name during Build` | `67e14bb6444965871221fa006ac53ff5a40cbe9132938d80a64fa4bcbe18648d` |
| `fn_sale_online_thai_v2` | Direct canonical-name update | `Resolve by object name during Build` | `ff297729a8a8db3b44750b93b5fffde132378dcfed885f43458ea56ed718d64b` |
| `fn_sale_online_vn` | Direct canonical-name update | `sql/functions/reportdb.fn_sale_online_vn.sql` | `38e9c1b737588a8a2fb50646984f72d58ccc8f556f3ed94b24035d5f2f5cd351` |
| `fn_sale_online_vn_product` | Direct canonical-name update | `sql/functions/reportdb.fn_sale_online_vn_product.sql` | `905c130cdbf18fc6883f7184206828c92771ffb6c0e3add07413f2871c521395` |
| `fn_sale_online_vn_v2` | Direct canonical-name update | `sql/functions/fn_sale_online_vn.sql` | `f76423ca8298c906f998fb59474a0d2cdfc9a23e3ec9f062d0eac4bf704677da` |
| `fn_sale_store_china` | Direct canonical-name update | `Resolve by object name during Build` | `649864ff086db7a8a9bf8334b346ff8f81c916367c2988c5320e5582f6699d7d` |
| `fn_sale_store_china_product` | Direct canonical-name update | `Resolve by object name during Build` | `720c606dae8cfdd39ba119b94d7821ab4a622c0320b094d7bb5999c49381eda6` |
| `fn_sale_store_china_v2` | Direct canonical-name update | `Resolve by object name during Build` | `df11bd90a6d0b889653d33364e0977d35f3733445515c48484d0f0d3368f6172` |
| `fn_sale_store_thai` | Direct canonical-name update | `sql/functions/reportdb.fn_sale_store_thai.sql` | `b3e005f8c8e2ea5d59f9b81874770753a7b26b5b920aa21b8b008fd0b6c97836` |
| `fn_sale_store_thai_product` | Direct canonical-name update | `sql/functions/reportdb.fn_sale_store_thai_product.sql` | `6429ad93244f19c042bfc871ec25688c499d3718ebd54932fd311829c5c67fa2` |
| `fn_sale_store_thai_v2` | Direct canonical-name update | `sql/functions/reportdb.fn_sale_store_thai_v2.sql` | `79dc3bbe0f97c04eeea5e0562ff99581d3d570588a00d905e48868ae7cafff4a` |
| `fn_sale_store_vn` | Direct canonical-name update | `sql/functions/warehouse_identity/fn_sale_store_vn.sql` | `7ade74b60b42f993193b8ead58556d9dad6539bbc18436811548fc452583db9f` |
| `fn_sale_store_vn_product` | Direct canonical-name update | `sql/functions/reportdb.fn_sale_store_vn_product.sql` | `2cab49ff566e5af8a2ccab6128cdb29de9c9588289a0db6b0e139276715d2bcc` |
| `fn_sale_store_vn_v2` | Direct canonical-name update | `sql/functions/reportdb.fn_sale_store_vn.sql` | `85420a713c57b83d9a56d1e229acf3fdfd5175be8bf125761c9b479f07784583` |
| `fn_sale_wholeshale_vn` | Direct canonical-name update | `Resolve by object name during Build` | `d2266f93f2791bfab1f9bfdf2c4bd2d93e6869bc5187c816d0ec6fdf6effa848` |
| `fn_sale_wholeshale_vn_product` | Direct canonical-name update | `Resolve by object name during Build` | `0c6a8a2e1175a88665dc51d347de90a44915fb04dd359ae6cc0bfb5b68021e56` |
| `fn_sale_wholeshale_vn_v2` | Direct canonical-name update | `Resolve by object name during Build` | `b4dbde9420fc40a1bc7c52e9e6e16a5af92ebf7ac3422d6181008062bf71d872` |
| `fn_stats_product` | Inherit corrected names / verify lineage | `Resolve by object name during Build` | `5d7c5468f9b4b6cff23e410520afbf18c813cad1a53f8dcae176d054cec2c17a` |
| `fn_stats_product_v2` | Direct canonical-name update | `Resolve by object name during Build` | `fd13c74de6424a29e52dc5d23b7d9dec49c55858ebe0e1f3c72203877884a6d4` |
| `fn_thailand_product_inventory` | Direct canonical-name update | `Resolve by object name during Build` | `c7c011c22af403e40efc0c7d8c920dc4699034192d4ac5b64f5030b1b132ee97` |

## Source artifacts

Private captures are in the current thread storage directory `warehouse-name-plan/`; do not copy raw routine comments or business data into public artifacts. The prior same-day warehouse-only history was re-read from thread `thr_qjwbpax4cj`, `warehouse-id-plan/warehouse-name-history.json`, SHA-256 `b1130cd38df29e0877782c2d54fa7de6189faeedcf63367b95dbe12fda6561bb`. It is historical evidence, not a new history query.

| Artifact | SHA-256 |
| --- | --- |
| `datasets.json` | `18fc1d7ad8529150397f94f7abd45a19aaa6193476a515e0d0d26d5594ed343b` |
| `dataset-locations.json` | `afa5a45ebdc574a42d39e17efb0ce416d3339512f5bd099a263996b6703ee6c3` |
| `all-routines.json` | `7b404d9fb36317de37b4cbff0b86f7eed1b8e0f7418e446cce856c8d4e14769d` |
| `current-warehouses.json` | `f5140cb7f7b0ef15a7374956e73f70ef1ed36795ffee8977930e4db048c60575` |

The twelve pending function baselines and warehouse-procedure baseline still match fresh live DDL exactly. Current core_warehouse has nineteen distinct nonempty IDs and exactly matches the ID-policy key set. No production changes or customer-row queries ran.

## Mapping evidence

- The seven predicate-membership IDs remain those in `sql/config/warehouse_policy.json`; use the nineteen-row mapping table in `plan.md` for prior history.
- All nine China sales functions explicitly pair their old label with `76be7836-6dc5-4b1c-9e48-b18e43127453`; current display name is `CN – Backup Stock (VN)`.
- Five Thai sales functions explicitly pair `Kho Ecommerce Thailand` or `Kho Thái (Back-up)` with `878504e9-fb75-4870-8504-b2ecdbc097ba`; Thai inventory pairs `Kho Thái Lan` with the same ID. Current display name is `TH – Backup Stock (VN)`.
- No fuzzy matching or new identity decision is necessary for the captured functions. A future unmapped literal or conflicting ID must block that slice and be clarified.

## Non-targets

The remaining fifteen functions have no warehouse-name dependency in the inspected function graph. Procedures are inventory context; preserve the previously prepared warehouse producer, but do not broaden this extension into other procedures, ingestion or dbt changes. The old snapshot remains immutable.
