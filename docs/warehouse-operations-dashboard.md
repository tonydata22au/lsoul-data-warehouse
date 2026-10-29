# LSOUL warehouse operations — Looker Studio

## Delivery and source

The canonical definition is [fn_warehouse_operations.sql](../sql/functions/fn_warehouse_operations.sql).
It is a reporting table function for `marine-cycle-484213-b4`, Singapore
(`asia-southeast1`), using Vietnam calendar dates. It reads metadata and billing;
it never runs an ingestion pipeline or changes a business table.

The function is prepared locally, not deployed. A live dashboard can use the three
**read-only inline queries**, generated from the same function body, without deploying it:

- [Overview source](../sql/monitoring/looker_studio_custom_query.sql)
- [Project billing source](../sql/monitoring/looker_studio_billing_query.sql)
- [Job drill-down source](../sql/monitoring/looker_studio_jobs_query.sql)

Regenerate these after editing the function:

```bash
python3 scripts/build_warehouse_monitor_queries.py
```

Creation of a reporting function, deployment of ingestion changes, and Git publication
are separate actions. The inline connector queries require no warehouse deployment.

## Five views, two A4 landscape pages

Use **A4 (1.41:1) Landscape**, or custom **1123 × 794 px** (297 × 210 mm at 96 dpi).
Use a white background, navy headings, teal success, amber warnings, and red failures.
Use at least 11 px labels; keep the detailed job table on page 2 rather than shrinking
all columns onto page 1. A PDF is an export snapshot; the live report supplies filters.

| View | Chart and fields | Question answered |
| --- | --- | --- |
| 1. Operations summary | Four scorecards: distinct tables with jobs; distinct tables with successes; summed execution hours / selected day; billed VND / selected day | Activity, successful destinations, runtime, cost |
| 2. Daily job outcomes | Stacked columns: `activity_date`, SUM success/failed/cancelled/running/pending counts. A runtime time series below uses total seconds and mean completed-job seconds | Job volume, outcomes, execution duration over 30 days |
| 3. Daily project spend | Time series: `activity_date`, SUM `billed_cost`, SUM `effective_cost`; currency VND. Subtitle: project wide, billing export may lag | Actual costs, including storage and applicable non-query SKUs |
| 4. Freshness and exceptions | Table: table name/type, freshness status, last successful write, missing write days, job failures, runtime/cost anomaly status, estimated query cost | 14-day gaps, irregular writes, anomalies, expensive destinations |
| 5. Job and lineage explorer | Page 2 table: table name/type, job ID, source tables, destination, original source, trigger, parent/procedure, load strategy, start/end, runtime, status, cost basis | Individual job history, lineage, provenance and attribution confidence |

Place page 1 header at `(32,24)`; controls at y=72; KPI cards at y=130 (four equal
columns); job/runtime charts at `(32,230)` with width 650; spend at `(710,230)` with
width 381; freshness table at `(32,470)` with width 1059 and height 250. Footer y=744.
The job outcomes and runtime panel can contain two aligned charts without becoming a
sixth analytical view. Page 2 uses the same header/controls with a full-width job table.

## Data connections and filters

For each source, choose Google BigQuery → Custom Query → billing project
`marine-cycle-484213-b4`. Enable **date range parameters** and paste its generated SQL.
The connector must execute in Singapore; location follows the referenced datasets.
Use the Operations Data LSOUL account and keep report sharing unchanged.

Set `activity_date` as the date-range dimension. Default **last 30 days, excluding
today**; timezone **Asia/Ho_Chi_Minh**. Both date parameters are inclusive strings
`YYYYMMDD`, parsed to DATE by the SQL. The function permits 1–90 selected days,
starting within 150 days of today, so its 28-day baseline fits the 180-day job history.

Add a searchable multi-select dropdown on `table_name`. Use the overview source for
page 1 controls and the jobs source for page 2. Date controls apply to all page charts.
The separate billing source deliberately has **no table-name field**: project spend
cannot truthfully be filtered to a table without a cost-allocation model. Label its
KPI/chart **Project cost — table filter does not apply**. The freshness table's
`estimated_query_cost` responds to the destination-table filter.

Use these aggregations, not Record Count:

| Display | Aggregation |
| --- | --- |
| Tables with jobs | COUNT_DISTINCT(`table_with_jobs`) |
| Tables with successes | COUNT_DISTINCT(`table_with_success`) |
| Avg execution hours / day | SUM(`runtime_seconds_per_selected_day`) / 3600 |
| Project billed VND / day | SUM(`billed_cost_per_selected_day`) from billing source |
| Jobs / successful / failed | SUM of the corresponding count field |
| Mean completed-job runtime | SUM(`total_runtime_seconds`) / SUM(`completed_runtime_count`) |
| Table estimated query cost | SUM(`estimated_query_cost`); show SUM(`unpriced_query_count`) alongside |

For freshness, filter `record_type = TABLE_DAY`; use MAX for the repeated 14-day
fields and timestamps. Use COUNT_DISTINCT(table_name), never SUM of a repeated
freshness flag across dates. For a compact table, show the freshness status and
MAX missing days, and enable drill-down to daily `anomaly_status` / `cost_anomaly_status`.
For daily anomalies, a row is one table-day, so count rows after filtering a specific
anomaly status; explicitly label that count **table-days**, not jobs.

A table with at least one successful job counts in “Tables with successes” even if
another job failed. These are destination-based KPIs, not counts of every source read.

## Function contract and caveats

`reportdb.fn_warehouse_operations(p_start_date DATE, p_end_date DATE)` defaults NULL
arguments to the last 30 complete Vietnam days. `selected_days` is the inclusive
calendar denominator, so days with no jobs remain in averages even after table filters.

| Record type | Unique key | Meaning |
| --- | --- | --- |
| TABLE_DAY | record_type + table_name + activity_date | Current catalog object crossed with selected date, including zero-job days |
| UNALLOCATED | record_type + activity_date | Jobs without a destination in the current visible catalog, including anonymous query results and dropped tables |
| PROJECT_BILLING | record_type + activity_date + currency | Project-level BigQuery billing export, never joined to each job |

Only additive metrics are summed. Rates, distinct counts, status, last timestamps,
and freshness counts are not additive. NULL cost means unavailable or not allocated,
not free. Calendar rows have zero job metrics, but unknown price/cost remains NULL.
The nested `job_details` array contains one non-script-parent job; it is flattened only
by the drill-down query. Never sum daily totals after unnesting this array.

Jobs are assigned by **creation date**; durations are end minus start for completed jobs.
Pending/running durations remain NULL and do not enter the mean. Runtime is execution
work summed across jobs, not pipeline wall-clock elapsed time; parallel jobs overlap.
SCRIPT parents are excluded from metrics; parent labels and procedure text are used
only for attribution. Jobs from other billing projects or other regions are not visible.

The inventory is live within the 22 visible datasets discovered on 2026-10-28. It is
not a historical inventory: deleted objects remain unallocated, new objects appear
on the calendar, and object type reflects today. Add newly created datasets to the
inventory UNION. Hidden temporary datasets are not claimed as covered. Missing
permissions cause a query error, not a fabricated “no jobs” result. Cross-project writes,
streaming/Storage Write API ingestion, and some managed refreshes can be absent from
this job log. Verify critical alerts against the pipeline's actual ingestion mechanism.

`source_tables` comes from referenced tables, and can be missing for cached queries.
The original business source is inferred from the destination dataset, not proven
end-to-end lineage. The daily source/trigger/strategy summaries are bounded (20/10/10
unique strings); individual job details preserve the full observed metadata.
Dataform, transfer, and Looker origin use job/parent labels. Procedure attribution is
inferred from a CALL in the parent SQL; nested/dynamic calls need audit/job configuration.
No email-based guesses about trigger identity are made; no raw SQL or actor emails
are returned to the dashboard.

INSERT/MERGE are incremental **candidates**; CTAS with CREATE OR REPLACE indicates
full rebuild. LOAD/COPY write disposition is **unknown** in JOBS metadata. Definitive
full/incremental load classification needs jobs.get configuration or a maintained
pipeline registry; a full source fetch can still append to a raw table.

### Freshness

Evaluate the 14 complete local days ending at `freshness_as_of` (selected end date,
or yesterday when today is selected), independent of a shorter display window.
A qualifying successful write is a successful LOAD/COPY/INSERT/MERGE/CTAS; success
proves job completion, not positive rows inserted or business-data freshness.
UPDATE/DELETE/TRUNCATE/SELECT/view-definition jobs do not reset ingestion freshness.

- **CRITICAL:** no successful qualifying write in those 14 days.
- **WARNING:** at least one successful write, but 8 or more of 14 days missing.
- **OK:** at least 7 days with a successful write under the daily assumption.
- **NEW:** current object created less than 14 complete days ago; insufficient history.
- **Weekly exception:** the 21 table outputs in the saved `ppl-AI` main branch use
  Monday 09:15 ICT cadence. No successful write in 14 days is critical; last success
  over 7 days ago warns; regular weekly writes do not trigger the daily-gap warning.
- **N/A / REVIEW:** logical/materialized views, external objects, snapshots/clones,
  dated shards, billing exports, analytics-managed exports, development and utility
  datasets need their own refresh policy. Their activity remains visible.

Other operational base tables use **DAILY_ASSUMED**, explicitly not a verified SLA.
Creation time can reset after replacement, so NEW can also mean recently recreated.
Last-attempt and last-success timestamps are bounded by the selected scan window
(29 days before selected start through end), not all-time history. Materialized-view
refresh freshness is not measured by this job-write rule.

### Anomalies

Use four preceding occurrences of the same weekday (28 days), including calendar
zeroes, with no future data in the baseline. A recent table or fewer than four baseline
observations is insufficient history. Failed jobs are always surfaced. Runtime spikes
exceed max(2×mean, mean+3×population stddev, 60 seconds); volume spikes exceed
max(2×mean, mean+3×stddev, 10 jobs); volume drops are below half the mean when the
baseline averages at least 10 jobs. Cost spikes use the 2×/3-sigma rule and require
four priced observations and no unpriced query jobs that day. This is a transparent
heuristic, not a statistical guarantee; holidays, schedule changes and mixed pipelines
can still explain an alert. Inspect the baseline values and the job explorer.

### Cost

Actual `billed_cost` and `effective_cost` come from the accessible FOCUS export,
filtered to this project and BigQuery/BigQuery Storage API services. They include
applicable storage and non-query charges. ChargePeriodStart is bucketed into Vietnam
days; it is not split across days if a charge spans midnight. Latest export timestamp
is exposed, but late adjustments and invoice reconciliation can change the figures.
Do not subtract credits again from the FOCUS-defined costs.

Table/job query estimates use billed bytes / 2^40 × the **same day's observed Singapore
analysis list price and currency** from that export. This avoids hard-coding a US rate
or treating VND as USD. Estimates are gross, exclude free tiers/credits/discounts, and
are not invoice totals. Capacity, external service pricing, CREATE_MODEL/CALL and
missing bytes/rates are unallocated. No slot-ms-to-money conversion is attempted.
Do not add estimated costs to actual billed costs.

## Verification and reproducibility

The 30-day live aggregate query completed successfully on 2026-10-28. Its job, runtime
and failure totals reconciled exactly to an independent direct JOBS query. The function
DDL dry-run and the synthetic integration test passed. Inventory metadata was readable
across all 22 listed datasets. Repository validation passed; 16 unit tests completed
with one pre-existing skip. Aggregate diagnostic results stay outside Git; this
repository is public.

A report draft named **LSOUL | Warehouse Operations** was created in the Operations Data
LSOUL Chrome profile. BigQuery connector authorization succeeded on 2026-10-28. The
three read-only queries are connected as embedded sources (`ds0`: table-day,
`ds1`: project billing, `ds2`: jobs and lineage). The report canvas is configured to
**1123 × 794 px**, with fit-to-width viewing. The report-wide custom date range is
today minus 30 days through today minus 1 day; the placed date control displayed
28 September–27 October 2026 during verification.

The table-day source also has calculated metrics for distinct tables with jobs,
distinct tables with successes, and average execution hours per selected day.
The live [report](https://datastudio.google.com/reporting/9f972b71-ce1e-4e7d-98f4-aac66fd9750c)
now contains an Overview page with the table-name dropdown, four summary cards,
a daily success/failure and runtime chart, a daily actual-billing chart, and a
table-day freshness/anomaly table. The Jobs and lineage page contains individual
jobs with source inference, inventory table name, actual destination, job ID,
status, start timestamp, referenced source tables, trigger, load strategy, object
type, and runtime. The explorer supports horizontal scrolling and wrapped text.
The displayed summary cards reconcile to the validated 30-day SQL aggregates.

Final filter interaction and layout verification are still pending. Chrome tab
switches interrupted the final editing pass. Resume the existing report rather
than creating another report or duplicating its connected sources. Raw job
timestamps are UTC; `activity_date` and the date-window boundaries use Vietnam time.

The synthetic integration test executes the **actual function body** with source CTEs
replaced by synthetic data. It verifies script-parent exclusion, one-count-per-job
with two source references, zero-day averages, failed-only freshness, sparse writes,
logical-view exemptions, and project billing isolation:

```bash
# Offline: print SELECT-only test SQL for inspection.
python3 scripts/validate_warehouse_monitor.py
# With authorization: submit synthetic data only to BigQuery.
python3 scripts/validate_warehouse_monitor.py --run
python3 scripts/validate_repo.py
python3 -m unittest discover -s tests
```

Use BigQuery dry-run and a maximum-bytes-billed limit before changing the live query.
The first production validation estimated about 1.82 GB processed; billing export and
job metadata volume can grow. Each dashboard refresh issues queries and can cost money.
A scheduled materialized monitoring store is an optional future optimization, not
part of this deployment.

## Sources and method

Verified 2026-10-28 against [BigQuery JOBS documentation](https://docs.cloud.google.com/bigquery/docs/information-schema-jobs),
[table functions](https://docs.cloud.google.com/bigquery/docs/table-functions),
[Looker Studio custom-query parameters](https://docs.cloud.google.com/data-studio/use-parameters-in-a-custom-query),
[report layout](https://docs.cloud.google.com/data-studio/report-and-page-layout), and
[Google's FOCUS guide](https://services.google.com/fh/files/misc/focus_guide_v1.pdf).
The [pipeline inventory](pipelines.md) and exported Dataform workflow/configuration
files establish repository-specific attribution and schedule exceptions.
[Untools Inversion](https://untools.co/inversion/) was used as a failure-prevention
check: test missing tables, duplicated metrics, unsupported lineage and misleading
cost allocation before treating the report as reliable.
