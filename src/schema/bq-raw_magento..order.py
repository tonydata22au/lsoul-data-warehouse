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
DATASET_ID = 'magento'  # Change this to your desired dataset name
TABLE_ID = 'raw_magento_order'  # Change this to your desired table name
LOCATION = 'asia-southeast1'


BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
SERVICE_ACCOUNT_FILE = Path(os.getenv("GOOGLE_APPLICATION_CREDENTIALS", str(DEFAULT_SERVICE_ACCOUNT_FILE)))
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))

# Partitioning Configuration
PARTITION_TYPE = bigquery.TimePartitioningType.DAY
PARTITION_FIELD = None  # None = partition by ingestion time (_PARTITIONTIME), or specify a field name
REQUIRE_PARTITION_FILTER = True

# Schema Definition - aligned with Magento order export
# Note: BigQuery field names cannot contain dots, using underscores instead.
# The dynamic actions_* and cost_per_action_type_* columns depend on the
# action types returned by the API. Add them to ACTION_FIELDS / CPAT_FIELDS
# when you know which ones appear in your export headers.
BASE_HEADERS = [
    "created_at",
    "updated_at",
    "increment_id",
    "entity_id",
    "order_currency_code",
    "state",
    "status",
    "customer_email",
    "customer_firstname",
    "customer_lastname",
    "customer_group_id",
    "customer_is_guest",
    "customer_note_notify",
    "email_sent",
    "is_virtual",
    "remote_ip",
    "store_id",
    "store_currency_code",
    "store_name",
    "shipping_description",
    "shipping_amount",
    "shipping_tax_amount",
    "discount_amount",
    "subtotal",
    "total_paid",
    "total_due",
    "grand_total",
    "total_item_count",
    "total_qty_ordered",
    # Items (one row per item)
    "items_item_id",
    "items_product_id",
    "items_parent_item_id",
    "items_sku",
    "items_name",
    "items_free_shipping",
    "items_qty_ordered",
    "items_qty_canceled",
    "items_qty_refunded",
    "items_qty_shipped",
    "items_no_discount",
    "items_discount_percent",
    "items_amount_refunded",
    "items_discount_amount",
    "items_original_price",
    "items_price",
    "items_price_incl_tax",
    "items_tax_amount",
    "items_tax_percent",
    "items_row_total_incl_tax",
    "items_row_total",
    # Billing address
    "billing_address_billing",
    "billing_address_entity_id",
    "billing_address_parent_id",
    "billing_address_email",
    "billing_address_firstname",
    "billing_address_lastname",
    "billing_address_telephone",
    "billing_address_street",
    "billing_address_city",
    "billing_address_postcode",
    "billing_address_region_code",
    "billing_address_region",
    "billing_address_country_id",
    # Payment
    "payment_parent_id",
    "payment_account_status",
    "payment_method",
    "payment_shipping_amount",
    "payment_shipping_captured",
    "payment_amount_authorized",
    "payment_amount_ordered",
    "payment_amount_paid",
    # Extra fee (from extension_attributes.mp_extra_fee, serialised as JSON string)
    "mp_extra_fee",
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