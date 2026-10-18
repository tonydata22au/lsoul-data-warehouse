#bq-raw_tiktok_ads
#!/usr/bin/env python3
"""
Script to create BigQuery table with predefined schema.
Default: Creates empty table with schema only.

Usage:
    python3 local-run/DDL/bq-create-schema-bigquery.py              # Create empty table with schema
"""
import os
from pathlib import Path
from google.cloud import bigquery
from google.cloud.exceptions import NotFound
from google.oauth2 import service_account

# ============================================================================
# CONFIGURATION - MODIFY THESE VALUES FOR DIFFERENT TABLES/DATASETS
# ============================================================================

# BigQuery Configuration
DATASET_ID = 'dianplus'
TABLE_ID = 'raw_dianplus_order_return'  # Change this to your desired table name
LOCATION = 'asia-southeast1'


BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
SERVICE_ACCOUNT_FILE = Path(os.getenv("GOOGLE_APPLICATION_CREDENTIALS", str(DEFAULT_SERVICE_ACCOUNT_FILE)))
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))

# Partitioning Configuration
PARTITION_TYPE = bigquery.TimePartitioningType.DAY
PARTITION_FIELD = None  # None = partition by ingestion time (_PARTITIONTIME), or specify a field name
REQUIRE_PARTITION_FILTER = True

# Schema Definition - aligned with meta ads insights export
# Note: BigQuery field names cannot contain dots, using underscores instead.
# The dynamic actions_* and cost_per_action_type_* columns depend on the
# action types returned by the API. Add them to ACTION_FIELDS / CPAT_FIELDS
# when you know which ones appear in your export headers.
BASE_HEADERS = [
    "brandId",
                "porderId",
                "orderId",
                "rorderId",
                "createTime",
                "applyTime",
                "returnTime",
                "lastModifyTime",
                "refundStatus",
                "orderType",
                "returnSource",
                "srcSystem",
                "returnType",
                "saleChannelId",
                "saleChannelDjId",
                "saleChannelCode",
                "saleShopDjId",
                "saleShopCode",
                "saleStaffDjId",
                "saleStaffCode",
                "deliverShopDjId",
                "deliverShopCode",
                "deliverChannelCode",
                "deliverStaffDjId",
                "deliverStaffCode",
                "returnShopDjId",
                "returnShopCode",
                "returnChannelCode",
                "returnStaffDjId",
                "returnStaffCode",
                "returnNum",
                "sumSuggestPrice",
                "returnMoney",
                "remark",
                "returnOrderItems_rorderItemId",
                "returnOrderItems_rorderId",
                "returnOrderItems_spuDjId",
                "returnOrderItems_spuCode",
                "returnOrderItems_skuDjId",
                "returnOrderItems_skuCode",
                        "returnOrderItems_colorCode",
                        "returnOrderItems_colorName",
                        "returnOrderItems_sizeCode",
                        "returnOrderItems_sizeName",
                        "returnOrderItems_returnAmount",
                        "returnOrderItems_suggestPrice",
                        "returnOrderItems_salePrice",
                        "returnOrderItems_dealPrice",
                        "returnOrderItems_sumSuggestPrice",
                        "returnOrderItems_sumSalePrice",
                        "returnOrderItems_returnMoney",
                        "returnOrderItems_returnStaffId",
                        "returnOrderItems_returnStaffDjId",
                        "returnOrderItems_returnStaffCode",
                        "returnOrderItems_cashDtos",
                        "returnOrderItems_uniqueCodes",
                        "returnOrderItems_payInfo",
                                "returnOrderItems_itemPayInfos_payMethodCode",
                                "returnOrderItems_itemPayInfos_payMethodDesc",
                                "returnOrderItems_itemPayInfos_custPayMethodCode",
                                "returnOrderItems_itemPayInfos_custPayMethodName",
                                "returnOrderItems_itemPayInfos_amt",
                                "returnOrderItems_itemPayInfos_totalAmt",
                    "serviceGuides_staffDjId",
                    "serviceGuides_staffCode",
                    "payInfos_payType",
                    "payInfos_payCode",
                    "payInfos_outPayChannelDesc",
                    "payInfos_amount",
                    "payInfos_otherAmount",
                    "payInfos_cardNum",
                    "payInfos_cardId",
                    "payInfos_cardDesc",
                    "payInfos_outPayId",
                    "payInfos_cashVoucherDtos",
                    "origOrder_orderId",
                    "origOrder_sumAmount",
                    "origOrder_sumSuggestPrice",
                    "origOrder_sumSalePrice",
                    "origOrder_sumDealPrice",
                    "origOrder_payInfos_payType",
                    "origOrder_payInfos_payCode",
                    "origOrder_payInfos_outPayChannelDesc",
                    "origOrder_payInfos_amount",
                    "origOrder_payInfos_otherAmount"
]

TABLE_SCHEMA = [bigquery.SchemaField(col, 'STRING') for col in (BASE_HEADERS)]

# ============================================================================
# END OF CONFIGURATION
# ============================================================================

def create_dataset_if_not_exists(client, dataset_id, location):
    """Create dataset if it doesn't exist"""
    dataset_ref = client.dataset(dataset_id)
    try:
        client.get_dataset(dataset_ref)
        print(f"✓ Dataset {dataset_id} already exists")
    except NotFound:
        dataset = bigquery.Dataset(dataset_ref)
        dataset.location = location
        client.create_dataset(dataset)
        print(f"✓ Created dataset {dataset_id} in {location}")
    return dataset_ref


def create_table_schema_only(client, table_ref, schema):
    """Create an empty table with the specified schema"""
    table = bigquery.Table(table_ref, schema=schema)
    
    # Add time partitioning
    table.time_partitioning = bigquery.TimePartitioning(
        type_=PARTITION_TYPE,
        field=PARTITION_FIELD,
        require_partition_filter=REQUIRE_PARTITION_FILTER
    )
    
    try:
        client.get_table(table_ref)
        print(f"⚠ Table {TABLE_ID} already exists. Dropping and recreating...")
        client.delete_table(table_ref)
    except NotFound:
        pass
    
    table = client.create_table(table)
    print(f"✓ Created empty table with {len(schema)} columns")
    return table



def main():
    # Initialize BigQuery client
    client = bigquery.Client(credentials=credentials, project=credentials.project_id)
    print(f"✓ Connected to BigQuery project: {client.project}")
    
    # Create dataset if needed
    dataset_ref = create_dataset_if_not_exists(client, DATASET_ID, LOCATION)
    
    # Create table reference
    table_ref = dataset_ref.table(TABLE_ID)
    
    print(f"\nConfiguration:")
    print(f"  - Dataset: {DATASET_ID}")
    print(f"  - Table: {TABLE_ID}")
    print(f"  - Location: {LOCATION}")
    print(f"  - Partitioning: {PARTITION_TYPE}")
    print(f"  - Partition field: {PARTITION_FIELD or '_PARTITIONTIME (ingestion time)'}")
    print(f"  - Partition filter required: {REQUIRE_PARTITION_FILTER}")
    
    # Create empty table with schema only
    table = create_table_schema_only(client, table_ref, TABLE_SCHEMA)
    
    print(f"\n✓ Table schema: {len(table.schema)} columns")
    print(f"✓ Table location: {client.project}.{DATASET_ID}.{TABLE_ID}")
    print("\n✅ Operation completed successfully!")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n✗ Error during import: {str(e)}")
        import traceback
        traceback.print_exc()
        exit(1)