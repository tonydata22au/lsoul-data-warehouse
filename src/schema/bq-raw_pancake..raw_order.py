#!/usr/bin/env python3
"""
Script to create BigQuery table with predefined schema.
Default: Creates empty table with schema only.
Use --csv flag to load data from CSV file.

Usage:
    python bq-create-schema-from-csv.py              # Create empty table with schema
    python bq-create-schema-from-csv.py --csv        # Create table and load CSV data
"""
import os
import argparse
from google.cloud import bigquery
from google.cloud.exceptions import NotFound

# ============================================================================
# CONFIGURATION - MODIFY THESE VALUES FOR DIFFERENT TABLES/DATASETS
# ============================================================================

# BigQuery Configuration
DATASET_ID = 'raw_pancake'
TABLE_ID = 'raw_order'
LOCATION = 'asia-southeast1'

# CSV Configuration (only used when --csv flag is provided)
CSV_PATH = '/Users/tony.pham/Library/CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/data_export_csv/pancake_raw_order_list_20260130183751.csv'

# Partitioning Configuration
PARTITION_TYPE = bigquery.TimePartitioningType.DAY
PARTITION_FIELD = None  # None = partition by ingestion time (_PARTITIONTIME), or specify a field name
REQUIRE_PARTITION_FILTER = True

# Schema Definition - Define your table columns here
TABLE_SCHEMA = [
    bigquery.SchemaField('_item_id_', 'STRING'),
    bigquery.SchemaField('product_id', 'STRING'),
    bigquery.SchemaField('variation_id', 'STRING'),
    bigquery.SchemaField('quantity_ordered', 'STRING'),
    bigquery.SchemaField('quantity_returned', 'STRING'),
    bigquery.SchemaField('quantity_returning', 'STRING'),
    bigquery.SchemaField('return_count', 'STRING'),
    bigquery.SchemaField('is_wholesale', 'STRING'),
    bigquery.SchemaField('is_discount_percent', 'STRING'),
    bigquery.SchemaField('is_one_time_product', 'STRING'),
    bigquery.SchemaField('cart_quantity', 'STRING'),
    bigquery.SchemaField('exchange_count', 'STRING'),
    bigquery.SchemaField('unit_discount', 'STRING'),
    bigquery.SchemaField('item_total_discount', 'STRING'),
    bigquery.SchemaField('product_name', 'STRING'),
    bigquery.SchemaField('exact_price', 'STRING'),
    bigquery.SchemaField('retail_price', 'STRING'),
    bigquery.SchemaField('original_retail_price', 'STRING'),
    bigquery.SchemaField('average_price', 'STRING'),
    bigquery.SchemaField('last_import_price', 'STRING'),
    bigquery.SchemaField('product_detail', 'STRING'),
    bigquery.SchemaField('product_fields', 'STRING'),
    bigquery.SchemaField('order_id', 'STRING'),
    bigquery.SchemaField('system_id', 'STRING'),
    bigquery.SchemaField('status', 'STRING'),
    bigquery.SchemaField('status_name', 'STRING'),
    bigquery.SchemaField('inserted_at', 'STRING'),
    bigquery.SchemaField('updated_at', 'STRING'),
    bigquery.SchemaField('is_received_at_shop', 'STRING'),
    bigquery.SchemaField('order_currency', 'STRING'),
    bigquery.SchemaField('total_price', 'STRING'),
    bigquery.SchemaField('total_price_after_sub_discount', 'STRING'),
    bigquery.SchemaField('total_discount', 'STRING'),
    bigquery.SchemaField('total_quantity', 'STRING'),
    bigquery.SchemaField('shipping_fee', 'STRING'),
    bigquery.SchemaField('marketplace_fee', 'STRING'),
    bigquery.SchemaField('partner_fee', 'STRING'),
    bigquery.SchemaField('surcharge_amount', 'STRING'),
    bigquery.SchemaField('buyer_total_amount', 'STRING'),
    bigquery.SchemaField('cod_money_to_collect', 'STRING'),
    bigquery.SchemaField('cod', 'STRING'),
    bigquery.SchemaField('tax_amount', 'STRING'),
    bigquery.SchemaField('paid_cash', 'STRING'),
    bigquery.SchemaField('prepaid_amount', 'STRING'),
    bigquery.SchemaField('transfer_amount', 'STRING'),
    bigquery.SchemaField('charged_by_card', 'STRING'),
    bigquery.SchemaField('charged_by_momo', 'STRING'),
    bigquery.SchemaField('charged_by_qrpay', 'STRING'),
    bigquery.SchemaField('bank_payments', 'STRING'),
    bigquery.SchemaField('exchange_payment_info', 'STRING'),
    bigquery.SchemaField('is_customer_paid_fee', 'STRING'),
    bigquery.SchemaField('shipping_address_commune_name', 'STRING'),
    bigquery.SchemaField('shipping_address_province_name', 'STRING'),
    bigquery.SchemaField('warehouse_id', 'STRING'),
    bigquery.SchemaField('warehouse_info_name', 'STRING'),
    bigquery.SchemaField('marketplace_id', 'STRING'),
    bigquery.SchemaField('order_sources', 'STRING'),
    bigquery.SchemaField('order_sources_name', 'STRING'),
    bigquery.SchemaField('ad_id', 'STRING'),
    bigquery.SchemaField('page_id', 'STRING'),
    bigquery.SchemaField('notes', 'STRING'),
    bigquery.SchemaField('print_notes', 'STRING'),
    bigquery.SchemaField('tags', 'STRING'),
    bigquery.SchemaField('customer_currency', 'STRING'),
    bigquery.SchemaField('customer_customer_id', 'STRING'),
    bigquery.SchemaField('customer_succeed_order_count', 'STRING'),
    bigquery.SchemaField('customer_inserted_at', 'STRING'),
    bigquery.SchemaField('customer_is_block', 'STRING'),
    bigquery.SchemaField('customer_updated_at', 'STRING'),
    bigquery.SchemaField('customer_order_count', 'STRING'),
    bigquery.SchemaField('customer_returned_order_count', 'STRING'),
    bigquery.SchemaField('customer_purchased_amount', 'STRING'),
    bigquery.SchemaField('customer_last_order_at', 'STRING'),
    bigquery.SchemaField('customer_gender', 'STRING'),
    bigquery.SchemaField('assigning_seller_name', 'STRING'),
    bigquery.SchemaField('assigning_seller_email', 'STRING'),
    bigquery.SchemaField('assigning_care_name', 'STRING'),
    bigquery.SchemaField('assigning_care_email', 'STRING'),
    bigquery.SchemaField('time_assigned_seller', 'STRING'),
    bigquery.SchemaField('time_assigned_care', 'STRING'),
    bigquery.SchemaField('time_sent_partner', 'STRING'),
    bigquery.SchemaField('is_exchange_order', 'STRING'),
    bigquery.SchemaField('exchange_value', 'STRING'),
    bigquery.SchemaField('return_reason_code', 'STRING'),
    bigquery.SchemaField('return_reason', 'STRING'),
    bigquery.SchemaField('last_editor_name', 'STRING'),
    bigquery.SchemaField('last_editor_email', 'STRING'),
    bigquery.SchemaField('creator_name', 'STRING'),
    bigquery.SchemaField('creator_email', 'STRING'),
    bigquery.SchemaField('partner', 'STRING'),
    bigquery.SchemaField('items_count', 'STRING'),
    bigquery.SchemaField('advanced_platform_fee_affiliate_commission', 'STRING'),
    bigquery.SchemaField('advanced_platform_fee_diff_shipping_fee', 'STRING'),
    bigquery.SchemaField('advanced_platform_fee_marketplace_voucher', 'STRING'),
    bigquery.SchemaField('advanced_platform_fee_payment_fee', 'STRING'),
    bigquery.SchemaField('advanced_platform_fee_seller_transaction_fee', 'STRING'),
    bigquery.SchemaField('advanced_platform_fee_service_fee', 'STRING'),
]

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


def load_csv_to_table(client, table_ref, csv_path, schema):
    """Load CSV data into the table"""
    # Verify CSV file exists
    if not os.path.exists(csv_path):
        print(f"✗ Error: CSV file not found at {csv_path}")
        exit(1)
    
    print(f"✓ CSV file found: {csv_path}")
    
    # Configure load job
    job_config = bigquery.LoadJobConfig()
    job_config.source_format = bigquery.SourceFormat.CSV
    job_config.skip_leading_rows = 1  # Header rows to skip
    job_config.write_disposition = bigquery.WriteDisposition.WRITE_TRUNCATE
    job_config.schema = schema
    
    # Time partitioning
    job_config.time_partitioning = bigquery.TimePartitioning(
        type_=PARTITION_TYPE,
        field=PARTITION_FIELD,
        require_partition_filter=REQUIRE_PARTITION_FILTER
    )
    
    print(f"Loading data from CSV to {DATASET_ID}.{TABLE_ID}...")
    
    with open(csv_path, 'rb') as source_file:
        job = client.load_table_from_file(source_file, table_ref, job_config=job_config)
    
    # Wait for the job to complete
    job.result()
    
    # Get table info
    table = client.get_table(table_ref)
    print(f"✓ Successfully loaded {table.num_rows:,} rows")
    return table


def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description='Create BigQuery table with schema. Use --csv to also load data from CSV.'
    )
    parser.add_argument(
        '--csv',
        action='store_true',
        help='Load data from CSV file (default: create empty table with schema only)'
    )
    args = parser.parse_args()
    
    # Initialize BigQuery client
    client = bigquery.Client()
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
    print(f"  - Mode: {'Load from CSV' if args.csv else 'Schema only (empty table)'}\n")
    
    if args.csv:
        # Load CSV data into table
        table = load_csv_to_table(client, table_ref, CSV_PATH, TABLE_SCHEMA)
    else:
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