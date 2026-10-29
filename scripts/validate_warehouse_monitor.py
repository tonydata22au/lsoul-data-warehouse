#!/usr/bin/env python3
"""Build a SELECT-only synthetic integration test; pass --run for BigQuery execution.

--run submits only synthetic values to BigQuery (requires explicit authorization).
The default prints SQL for inspection and makes no network call.
"""
import argparse
import subprocess
from build_warehouse_monitor_queries import query_body, ROOT


def extract_cte(sql, name):
    start = sql.index(name + ' AS (') + len(name + ' AS (')
    # The fixtures deliberately contain no closing parenthesis inside string literals.
    depth = 1
    for end in range(start, len(sql)):
        depth += (sql[end] == '(') - (sql[end] == ')')
        if depth == 0:
            return sql[start:end]
    raise ValueError(name)


def synthetic_query():
    body = query_body().replace('p_start_date', 'CAST(NULL AS DATE)').replace('p_end_date', 'CAST(NULL AS DATE)')
    fixture = (ROOT / 'sql/monitoring/fixtures.sql').read_text()
    for name, following in [('inventory_raw','inventory'),('jobs_raw','jobs_enriched'),('billing_raw','rates')]:
        start = body.index(name+' AS (')
        end = body.index(following+' AS (', start)
        body = body[:start]+name+' AS ('+extract_cte(fixture,name)+'\n),\n'+body[end:]
    return 'WITH monitor AS (\n'+body+'''\n), assertions AS (
SELECT
  SUM(job_count)=17 AS leaf_jobs_once,
  SUM(total_runtime_seconds)=170 AS parent_runtime_excluded,
  COUNT(DISTINCT table_with_jobs)=3 AS tables_with_jobs,
  COUNT(DISTINCT table_with_success)=2 AS successful_tables,
  SUM(failed_count)=1 AS failed_jobs,
  COUNTIF(record_type='TABLE_DAY')=120 AS inventory_date_spine,
  COUNTIF(ENDS_WITH(table_name,'.critical') AND freshness_status='CRITICAL')=30 AS failed_only_is_stale,
  COUNTIF(ENDS_WITH(table_name,'.warning') AND freshness_status='WARNING')=30 AS sparse_is_warning,
  COUNTIF(ENDS_WITH(table_name,'.daily_ok') AND freshness_status='OK')=30 AS daily_is_healthy,
  COUNTIF(ENDS_WITH(table_name,'.logical_view') AND freshness_status='N/A: VIEW')=30 AS view_is_exempt,
  SUM(billed_cost)=3000 AS project_billing_not_multiplied,
  SUM(estimated_query_cost)=17000 AS estimate_not_fanned_out,
  ABS(SUM(runtime_seconds_per_selected_day)-170.0/30)<0.0001 AS zero_days_in_denominator
FROM monitor
)
SELECT IF(STRPOS(TO_JSON_STRING(a),'false')=0,'PASS',ERROR(TO_JSON_STRING(a))) AS result
FROM assertions a
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',action='store_true')
    args=parser.parse_args()
    sql=synthetic_query()
    if not args.run:
        print(sql)
        return
    result=subprocess.run(['bq','--project_id=marine-cycle-484213-b4','--location=asia-southeast1',
      '--format=json','query','--use_legacy_sql=false','--label=datacloud:codex',
      '--maximum_bytes_billed=100000000'],input=sql,text=True)
    raise SystemExit(result.returncode)


if __name__=='__main__':
    main()
