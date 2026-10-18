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
from pathlib import Path
import argparse
import pandas as pd
from google.cloud import bigquery
from google.cloud.exceptions import NotFound
from google.oauth2 import service_account

# ============================================================================
# CONFIGURATION - MODIFY THESE VALUES FOR DIFFERENT TABLES/DATASETS
# ============================================================================

# BigQuery Configuration
DATASET_ID = 'raw_pancake'
TABLE_ID = 'raw_stats_inventory_variations'
LOCATION = 'asia-southeast1'

# CSV Configuration (only used when --csv flag is provided)
CSV_PATH = '/Users/tony.pham/Library/' #CloudStorage/GoogleDrive-ops.data@lsoul.com/My Drive/03. CODE & DOCUMENTS/data_export_csv/pancake_raw_order_list_20260130183751.csv'

BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_SERVICE_ACCOUNT_FILE = BASE_DIR / "credentials" / "google-credentials.json"
SERVICE_ACCOUNT_FILE = Path(os.getenv("GOOGLE_APPLICATION_CREDENTIALS", str(DEFAULT_SERVICE_ACCOUNT_FILE)))
credentials = service_account.Credentials.from_service_account_file(str(SERVICE_ACCOUNT_FILE))

# Partitioning Configuration
PARTITION_TYPE = bigquery.TimePartitioningType.DAY
PARTITION_FIELD = None  # None = partition by ingestion time (_PARTITIONTIME), or specify a field name
REQUIRE_PARTITION_FILTER = True

# Schema Definition - Define your table columns here
# Note: BigQuery field names cannot contain dots, using underscores instead
TABLE_SCHEMA = [
    bigquery.SchemaField('stats_id', 'STRING'),
    bigquery.SchemaField('variation_id', 'STRING'),
    bigquery.SchemaField('variation_custom_id', 'STRING'),
    bigquery.SchemaField('variation_display_id', 'STRING'),
    bigquery.SchemaField('variation_fields', 'STRING'),
    bigquery.SchemaField('variation_product_id', 'STRING'),
    bigquery.SchemaField('variation_product_custom_id', 'STRING'),
    bigquery.SchemaField('variation_product_display_id', 'STRING'),
    bigquery.SchemaField('variation_product_inserted_at', 'STRING'),
    bigquery.SchemaField('variation_product_name', 'STRING'),
    bigquery.SchemaField('begin_inventory', 'STRING'),
    bigquery.SchemaField('begin_inventory_value', 'STRING'),
    bigquery.SchemaField('end_inventory', 'STRING'),
    bigquery.SchemaField('end_inventory_value', 'STRING'),
    bigquery.SchemaField('purchase_export', 'STRING'),
    bigquery.SchemaField('purchase_import', 'STRING'),
    bigquery.SchemaField('return_import', 'STRING'),
    bigquery.SchemaField('sell_export', 'STRING'),
    bigquery.SchemaField('stocktaking_export', 'STRING'),
    bigquery.SchemaField('stocktaking_import', 'STRING'),
    bigquery.SchemaField('total_export', 'STRING'),
    bigquery.SchemaField('total_export_value', 'STRING'),
    bigquery.SchemaField('total_import', 'STRING'),
    bigquery.SchemaField('total_import_value', 'STRING'),
    bigquery.SchemaField('transfer_export', 'STRING'),
    bigquery.SchemaField('transfer_import', 'STRING')

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