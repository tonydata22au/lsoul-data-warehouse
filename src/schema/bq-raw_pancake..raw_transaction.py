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
TABLE_ID = 'raw_transaction'
LOCATION = 'asia-southeast1'

# CSV Configuration (only used when --csv flag is provided)
CSV_PATH = '/Users/tony.pham/Library/' #CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/data_export_csv/pancake_raw_order_list_20260130183751.csv'

# Partitioning Configuration
PARTITION_TYPE = bigquery.TimePartitioningType.DAY
PARTITION_FIELD = None  # None = partition by ingestion time (_PARTITIONTIME), or specify a field name
REQUIRE_PARTITION_FILTER = True

# Schema Definition - Define your table columns here
# Note: BigQuery field names cannot contain dots, using underscores instead
TABLE_SCHEMA = [
    bigquery.SchemaField('inserted_at', 'STRING'),
    bigquery.SchemaField('transaction_id', 'STRING'),
    bigquery.SchemaField('ref_id', 'STRING'),
    bigquery.SchemaField('status', 'STRING'),
    bigquery.SchemaField('type_transaction', 'STRING'),
    bigquery.SchemaField('name', 'STRING'),
    bigquery.SchemaField('display_id', 'STRING'),
    bigquery.SchemaField('account', 'STRING'),
    bigquery.SchemaField('creator_name', 'STRING'),
    bigquery.SchemaField('creator_id', 'STRING'),
    bigquery.SchemaField('posted_at', 'STRING'),
    bigquery.SchemaField('is_canceled', 'STRING'),
    bigquery.SchemaField('advertising_cost_id', 'STRING'),
    bigquery.SchemaField('warehouse_id', 'STRING'),
    bigquery.SchemaField('amount', 'STRING'),
    bigquery.SchemaField('is_accounting', 'STRING'),
    bigquery.SchemaField('ref_display_id', 'STRING'),
    bigquery.SchemaField('is_locked', 'STRING'),
    bigquery.SchemaField('payments', 'STRING'),
    bigquery.SchemaField('currency', 'STRING'),
    bigquery.SchemaField('source', 'STRING'),
    bigquery.SchemaField('is_removed', 'STRING'),
    bigquery.SchemaField('is_locked_by_user', 'STRING'),
    bigquery.SchemaField('order_id', 'STRING'),
    bigquery.SchemaField('order_display_id', 'STRING'),
    bigquery.SchemaField('order_inserted_at', 'STRING'),
    bigquery.SchemaField('order_account', 'STRING'),
    bigquery.SchemaField('order_cod', 'STRING'),
    bigquery.SchemaField('order_sources', 'STRING'),
    bigquery.SchemaField('order_partner_id', 'STRING'),
    bigquery.SchemaField('order_received_at_shop', 'STRING'),
    bigquery.SchemaField('order_return_money', 'STRING'),
    bigquery.SchemaField('order_return_transfer_money', 'STRING'),
    bigquery.SchemaField('shipping_address_commnue_name', 'STRING'),
    bigquery.SchemaField('shipping_address_province_name', 'STRING'),
    bigquery.SchemaField('order_third_party_information_name', 'STRING'),
    bigquery.SchemaField('order_custom_id', 'STRING'),
    bigquery.SchemaField('order_item_id', 'STRING'),
    bigquery.SchemaField('order_item_inserted_at', 'STRING'),
    bigquery.SchemaField('order_item_returned_count', 'STRING'),
    bigquery.SchemaField('order_item_one_time_product', 'STRING'),
    bigquery.SchemaField('order_item_is_fixed_prices', 'STRING'),
    bigquery.SchemaField('order_item_returning_quantity', 'STRING'),
    bigquery.SchemaField('order_item_is_wholesale', 'STRING'),
    bigquery.SchemaField('order_item_quantity', 'STRING'),
    bigquery.SchemaField('order_item_variation_warehouse_id', 'STRING'),
    bigquery.SchemaField('order_item_discount', 'STRING'),
    bigquery.SchemaField('order_items_assigning_seller_id', 'STRING'),
    bigquery.SchemaField('order_item_product_id', 'STRING'),
    bigquery.SchemaField('order_item_added_to_cart_quantity', 'STRING'),
    bigquery.SchemaField('order_item_parent_item_id', 'STRING'),
    bigquery.SchemaField('order_item_discount_each_product', 'STRING'),
    bigquery.SchemaField('order_item_add_to_cart', 'STRING'),
    bigquery.SchemaField('order_item_is_discount_percent', 'STRING'),
    bigquery.SchemaField('order_item_variation_id', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_id', 'STRING'),           
    bigquery.SchemaField('order_item_variation_info_inserted_at', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_custom_id', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_supplier_product_ids', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_wholesale_price', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_name', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_price_at_counter', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_exact_price', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_retail_price_by_currency', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_type', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_images', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_sort_variation_attributes', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_wholesale_price_original', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_retail_price', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_retail_price_by_weight', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_in_promotions', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_retail_price_currency_original', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_fields', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_weight', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_detail', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_last_imported_price', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_retail_price_wholesale_original', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_is_sell_negative', 'STRING'),
    bigquery.SchemaField('order_item_variation_info_avg_price', 'STRING'),
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