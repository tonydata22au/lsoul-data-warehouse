# Warehouse operations monitoring

See the [dashboard guide](../../docs/warehouse-operations-dashboard.md) for metric
definitions, A4 landscape layout, date/table filters, costs and coverage limitations.

The single canonical reporting function is
[fn_warehouse_operations.sql](../functions/fn_warehouse_operations.sql). It is not
installed by these files. The `looker_studio_*.sql` files contain its SELECT body,
so the report can work without function deployment; enable `DS_START_DATE` and
`DS_END_DATE` date-range parameters in each BigQuery connector.

Regenerate connector files with `python3 scripts/build_warehouse_monitor_queries.py`.
`examples.sql` assumes the function has been deployed. `fixtures.sql` is synthetic
input for `scripts/validate_warehouse_monitor.py`; it contains no warehouse data.
