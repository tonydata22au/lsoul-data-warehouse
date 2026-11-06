"""HTTP route and CLI outcomes for every Cloud Run service (offline, mocked).

A scheduler only sees the HTTP status, and an operator only sees the CLI exit code, so:
- a fetch failure or a load failure must be non-2xx (route) / non-zero (CLI), with no
  claim that rows loaded, and no load job after a fetch failure;
- a legitimately empty source is a 2xx with no load job (VALID EMPTY), distinct from failure;
- a successful run is a 2xx with exactly one load to the expected raw table.

Fetch functions are replaced by synthetic records (tests/cloud_run_harness.py) or the HTTP
client fails; the services' transforms, routes and load paths are real. Needs the services'
requirements (see tests/test_cloud_run_destinations.py for how to run).
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_run_harness as harness  # noqa: E402
from test_cloud_run_destinations import EXPECTED_TABLES, PROJECT  # noqa: E402

# Words a response uses to claim rows were loaded
SUCCESS_CLAIMS = ("Success", "Loaded ", "Export completed", "rows_inserted")
# cloud-run-magento-order has no CLI: running the file starts the Flask server instead
NO_CLI = {"cloud-run-magento-order"}

RESULTS = {}


def scenarios(service):
    stubs, empty = harness.fetch_stubs(service), harness.fetch_stubs(service, empty=True)
    cases = [
        harness.scenario(service, "route_success", action="route", stubs=stubs),
        harness.scenario(service, "route_load_fails", action="route", stubs=stubs, load_error=True),
        harness.scenario(service, "route_fetch_connection_error", action="route", http="conn_error"),
        harness.scenario(service, "route_fetch_http_500", action="route", http="http_500"),
        harness.scenario(service, "route_valid_empty", action="route", stubs=empty),
    ]
    if service not in NO_CLI:
        cases += [
            harness.scenario(service, "cli_success", action="cli", stubs=stubs),
            harness.scenario(service, "cli_fetch_connection_error", action="cli", http="conn_error"),
            harness.scenario(service, "cli_load_fails", action="cli", stubs=stubs, load_error=True),
        ]
    return cases


def setUpModule():
    problem = harness.service_python_problem()
    if problem:
        raise unittest.SkipTest(problem)
    RESULTS.update(harness.run_all(scenarios))


def is_2xx(status):
    return status is not None and 200 <= status < 300


class Base(unittest.TestCase):
    def result(self, service, name):
        result = RESULTS[service][name]
        self.assertNotIn("import_error", result, result.get("traceback"))
        self.assertIsNone(result["harness_abort"], result["harness_abort"])
        return result


class RouteSuccess(Base):
    def test_success_is_2xx_with_one_load_to_the_expected_table(self):
        for service, table in EXPECTED_TABLES.items():
            with self.subTest(service=service):
                result = self.result(service, "route_success")
                self.assertTrue(is_2xx(result["status"]), (result["status"], result["body"]))
                self.assertEqual([load["destination"] for load in result["loads"]], [f"{PROJECT}.raw.{table}"])
                self.assertEqual(result["key_file_reads"], [])

    def test_success_logs_the_destination_job_id_and_rows(self):
        # Lets an operator tie a scheduler attempt to its BigQuery job from the service logs alone
        for service, table in EXPECTED_TABLES.items():
            with self.subTest(service=service):
                result = self.result(service, "route_success")
                rows = result["loads"][0]["rows"]
                # one line carries the row count, the destination and the job ID together
                line = rf"(?m)^.*\b{rows} rows\b.*\braw\.{table}\b.*\[harness-load-\d+\].*$"
                self.assertRegex(result["output_tail"], line)

    def test_valid_empty_is_2xx_without_a_load(self):
        for service in EXPECTED_TABLES:
            with self.subTest(service=service):
                result = self.result(service, "route_valid_empty")
                self.assertTrue(is_2xx(result["status"]), (result["status"], result["body"]))
                self.assertEqual(result["loads"], [])


class RouteFailures(Base):
    def assert_failure(self, result, expect_load_attempt):
        self.assertFalse(is_2xx(result["status"]), (result["status"], result["body"]))
        for claim in SUCCESS_CLAIMS:
            self.assertNotIn(claim, result["body"] or "")
        self.assertEqual(len(result["loads"]), 1 if expect_load_attempt else 0)

    def test_load_failure_is_not_2xx(self):
        for service in EXPECTED_TABLES:
            with self.subTest(service=service):
                # exactly one load was attempted, so the failure came from BigQuery, not the fixture
                self.assert_failure(self.result(service, "route_load_fails"), expect_load_attempt=True)

    def test_fetch_connection_error_is_not_2xx_and_loads_nothing(self):
        for service in EXPECTED_TABLES:
            with self.subTest(service=service):
                self.assert_failure(self.result(service, "route_fetch_connection_error"), expect_load_attempt=False)

    def test_fetch_http_500_is_not_2xx_and_loads_nothing(self):
        for service in EXPECTED_TABLES:
            with self.subTest(service=service):
                self.assert_failure(self.result(service, "route_fetch_http_500"), expect_load_attempt=False)


class Cli(Base):
    def services(self):
        return [s for s in EXPECTED_TABLES if s not in NO_CLI]

    def test_cli_success_exits_zero_after_one_load(self):
        # guards the failure cases below: a non-zero exit there is not an argument error
        for service in self.services():
            with self.subTest(service=service):
                result = self.result(service, "cli_success")
                self.assertEqual(result["exit_code"], 0, result["exception"])
                self.assertEqual(len(result["loads"]), 1)

    def test_cli_fetch_failure_exits_non_zero_without_a_load(self):
        for service in self.services():
            with self.subTest(service=service):
                result = self.result(service, "cli_fetch_connection_error")
                self.assertNotEqual(result["exit_code"], 0, result["output_tail"][-300:])
                self.assertEqual(result["loads"], [])

    def test_cli_load_failure_exits_non_zero(self):
        for service in self.services():
            with self.subTest(service=service):
                result = self.result(service, "cli_load_fails")
                self.assertNotEqual(result["exit_code"], 0, result["output_tail"][-300:])
                self.assertEqual(len(result["loads"]), 1)

    def test_magento_has_no_cli_path(self):
        self.assertEqual(NO_CLI, {"cloud-run-magento-order"})
        self.assertNotIn("cli_success", RESULTS["cloud-run-magento-order"])


if __name__ == "__main__":
    unittest.main()
