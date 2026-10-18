#bq-raw_tiktok_ads
#!/usr/bin/env python3
"""
Script to create BigQuery table with predefined schema.
Default: Creates empty table with schema only.

Usage:
    python3 local-run/DDL/bq-create-schema-bigquery.py              # Create empty table with schema
    python3 versions/bq-raw_pancake..raw_product_variations.py              # Create empty table with schema
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
DATASET_ID = 'raw_pancake'  # Change this to your desired dataset name
TABLE_ID = 'raw_product_variations'  # Change this to your desired table name
LOCATION = 'asia-southeast1'


BASE_DIR = Path(__file__).resolve().parents[1] / "local-run"
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
   #Variation-level fields (from API response):
    "updated_at",
    "inserted_at",
    "variation_id",
    "variation_display_id",
    "size_name",
    "size_value",
    "color_name",
    "color_value",
    # --- Pricing & Costs ---
    "retail_price",
    "retail_price_after_discount",
    "average_imported_price",
    "last_imported_price",
    "total_purchase_price",
    "price_at_counter",
    "wholesale_price",
    # --- Stock & Status ---
    "remain_quantity",
    "is_hidden",
    "is_locked",
    "is_removed",
    "is_sell_negative",
    "is_composite",
    #"barcode": "variation_barcode",
    #"price_table": "variation_price_table",
    #"weight": "product_weight",
    #"images": "images",
    #"videos": "variation_videos",
    #"composite_products": "composite_components",
    #"bonus_variations": "bonus_variations",
    
    #Product-level fields (from 'product' nested object):
    "product_inserted_at",
    "product_id",
    "product_display_id",
    "product_name",
    "product_attributes",
    "product_internal_note",
    "product_public_note",
    "product_supplier_product_ids",
    "product_tags",
    #"product_measure_group_id",
    #"product_is_published",
    #"product_image",
    #"product_categories",

    #Variation-warehouse level fields (from 'variations_warehouses' nested object):
    "variations_warehouses_warehouse_id",
    "variations_warehouses_actual_remain_quantity",
    "variations_warehouses_pending_quantity",
    "variations_warehouses_remain_quantity",
    "variations_warehouses_total_quantity",
    "variations_warehouses_returning_quantity",
    "variations_warehouses_waiting_quantity",
    #"variations_warehouses_selling_avg",
     #"product_manipulation_warehouses"
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