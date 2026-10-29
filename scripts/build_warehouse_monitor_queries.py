#!/usr/bin/env python3
"""Generate read-only Looker queries from the single canonical TVF. No cloud calls."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'sql/functions/fn_warehouse_operations.sql'
OUTPUT = ROOT / 'sql/monitoring'


def query_body():
    source = SOURCE.read_text()
    return 'WITH\n' + source.split(') AS (\nWITH\n', 1)[1].rsplit('\n);', 1)[0]


def main():
    body = query_body().replace('p_start_date', "PARSE_DATE('%Y%m%d', @DS_START_DATE)")
    body = body.replace('p_end_date', "PARSE_DATE('%Y%m%d', @DS_END_DATE)")
    prefix = '-- Generated from fn_warehouse_operations.sql. Enable date-range parameters.\nWITH monitor AS (\n' + body + '\n)\n'
    queries = {
        'looker_studio_custom_query.sql': 'SELECT * EXCEPT(job_details) FROM monitor WHERE record_type != \'PROJECT_BILLING\'\n',
        'looker_studio_billing_query.sql': 'SELECT activity_date, currency, billed_cost, effective_cost, billed_cost_per_selected_day, billing_last_export FROM monitor WHERE record_type = \'PROJECT_BILLING\'\n',
        'looker_studio_jobs_query.sql': 'SELECT m.activity_date, m.table_name, m.table_type, m.original_source_inferred, j.* FROM monitor m, UNNEST(m.job_details) j\n',
    }
    for filename, suffix in queries.items():
        (OUTPUT / filename).write_text(prefix + suffix)
    print('Generated three read-only connector queries; no function deployment required.')


if __name__ == '__main__':
    main()
