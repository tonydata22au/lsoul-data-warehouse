"""Every Cloud Run service loads into marine-cycle-484213-b4.raw.<its table> (offline, mocked).

Each service runs in an isolated subprocess (tests/cloud_run_harness.py): sockets blocked,
dotenv disabled, a recording fake bigquery.Client, no key file. The expected destinations
below are literals taken from the live inventory read on 2026-11-05
(tasks/raw-dataset-plan.md, "Live inventory") and its list of tables that exist only in
code. They are deliberately not derived from the services' own constants.

Needs the services' requirements: run with that interpreter, or set LSOUL_SERVICE_PYTHON.
    LSOUL_SERVICE_PYTHON=<venv>/bin/python python3 -m unittest tests.test_cloud_run_destinations -v
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_run_harness as harness  # noqa: E402

PROJECT = "marine-cycle-484213-b4"

# service folder -> table it appends to. LIVE = in the 2026-11-05 inventory; CODE = not live yet.
EXPECTED_TABLES = {
    "cloud-run-dianplus-inventory": "raw_dianplus_inventory",  # LIVE (old dataset: dianplus)
    "cloud-run-dianplus-order": "raw_dianplus_order",  # LIVE (old dataset: dianplus)
    "cloud-run-dianplus-order-refund": "raw_dianplus_order_refund",  # LIVE (old dataset: dianplus)
    "cloud-run-dianplus-product": "raw_dianplus_product",  # LIVE (old dataset: dianplus)
    "cloud-run-jushuitan-order": "raw_jushuitan_order",  # CODE (not in the live inventory)
    "cloud-run-magento-order": "raw_magento_order",  # LIVE (old dataset: magento)
    "cloud-run-meta-ads-reporting-a": "raw_ads_reporting_a",  # LIVE (old dataset: raw_meta)
    "cloud-run-meta-ads-reporting-ecom": "raw_ads_reporting_ecom",  # LIVE (old dataset: raw_meta)
    "cloud-run-pancake-customer": "raw_customer",  # LIVE (old dataset: raw_pancake)
    "cloud-run-pancake-ecom-product": "raw_ecom_product",  # CODE
    "cloud-run-pancake-inventory_histories": "raw_inventory_histories",  # LIVE
    "cloud-run-pancake-order": "raw_order",  # LIVE
    # Fetches ordinary /orders, a copy of pancake-order (decision 4 in the plan): pinned as-is.
    "cloud-run-pancake-order_returned": "raw_order",  # LIVE
    "cloud-run-pancake-product": "raw_product",  # CODE
    "cloud-run-pancake-product_variations": "raw_product_variations",  # LIVE
    "cloud-run-pancake-stats_inventory_product": "raw_stats_inventory_product",  # CODE
    "cloud-run-pancake-stats_inventory_variations": "raw_stats_inventory_variations",  # LIVE
    "cloud-run-pancake-stats_order": "raw_stats_order",  # CODE
    "cloud-run-pancake-stats_product": "raw_stats_product",  # LIVE
    "cloud-run-pancake-variations": "raw_variations",  # CODE
    "cloud-run-pancake-warehouse_transfer": "raw_warehouse_transfers_completed",  # CODE
    "cloud-run-surfosm-inventory": "raw_surfosm_inventory",  # LIVE (old dataset: surfosm)
    "cloud-run-surfosm-order": "raw_surfosm_order",  # LIVE (old dataset: surfosm)
    "cloud-run-surfosm-order_return": "raw_surfosm_order_return",  # LIVE (old dataset: surfosm)
    "cloud-run-tiktok-ads": "raw_tiktok_ads",  # LIVE (old dataset: raw_tiktok)  VN account
    "cloud-run-tiktok-gmv-max-report": "raw_tiktok_gmv_max_report",  # LIVE  VN
    "cloud-run-tiktok-reporting-basic-autction-ad": "raw_tiktok_reporting_basic_auction_ad",  # LIVE  VN
    "cloud-run-tiktok-thai-ads": "raw_tiktok_thai_ads",  # LIVE  TH account
    "cloud-run-tiktok-thai-gmv-max-report": "raw_tiktok_thai_gmv_max_report",  # LIVE  TH
    "cloud-run-tiktok-thai-reporting-basic-autction-ad": "raw_tiktok_thai_reporting_basic_auction_ad",  # LIVE  TH
}

# Services whose dataset/table/project come from other variables (BQ_RAW_DATASET is ignored)
OWN_CONFIG = {
    "cloud-run-magento-order": {"BQ_PROJECT": "harness-project", "BQ_DATASET": "harness_ds", "BQ_TABLE": "harness_tbl"},
    "cloud-run-surfosm-inventory": {"BQ_DATASET": "harness_ds", "BQ_TABLE": "harness_tbl"},
}
OVERRIDE_DATASET = "harness_override"

RESULTS = {}


def default_scenarios(service):
    call = harness.load_call(service)
    return [
        harness.scenario(service, "load", **call),
        harness.scenario(service, "load_fails", load_error=True, **call),
        harness.scenario(service, "load_dataset_missing", dataset_missing=True, **call),
    ]


def override_scenarios(service):
    return [harness.scenario(service, "load", **harness.load_call(service))]


def override_env(service):
    return OWN_CONFIG.get(service, {"BQ_RAW_DATASET": OVERRIDE_DATASET})


def ignored_env(service):
    # For the two OWN_CONFIG services, a stray BQ_RAW_DATASET must not move them
    return {"BQ_RAW_DATASET": OVERRIDE_DATASET}


def setUpModule():
    problem = harness.service_python_problem()
    if problem:
        raise unittest.SkipTest(problem)
    RESULTS["default"] = harness.run_all(default_scenarios)
    RESULTS["override"] = harness.run_all(override_scenarios, env_for=override_env)
    RESULTS["other_adc_project"] = {
        service: {r["name"]: r for r in harness.run_service(service, override_scenarios(service),
                                                             adc_project="adc-runtime-project")}
        for service in ("cloud-run-pancake-customer", "cloud-run-tiktok-thai-ads", "cloud-run-surfosm-inventory",
                        "cloud-run-magento-order", "cloud-run-meta-ads-reporting-ecom")
    }
    RESULTS["ignored"] = {
        service: {r["name"]: r for r in harness.run_service(service, override_scenarios(service), env=ignored_env(service))}
        for service in OWN_CONFIG
    }


class Coverage(unittest.TestCase):
    def test_every_service_folder_has_an_expected_destination(self):
        self.assertEqual(sorted(EXPECTED_TABLES), harness.all_services())

    def test_tables_keep_vn_th_and_account_distinctions(self):
        tables = list(EXPECTED_TABLES.values())
        # The only shared destination is the pinned pancake-order_returned copy of pancake-order
        shared = {t for t in tables if tables.count(t) > 1}
        self.assertEqual(shared, {"raw_order"})


class DefaultDestination(unittest.TestCase):
    def result(self, service, name="load"):
        result = RESULTS["default"][service][name]
        self.assertNotIn("import_error", result, result.get("traceback"))
        return result

    def test_loads_append_to_the_raw_dataset(self):
        for service, table in EXPECTED_TABLES.items():
            with self.subTest(service=service):
                result = self.result(service)
                self.assertIsNone(result["exception"])
                self.assertEqual([load["destination"] for load in result["loads"]], [f"{PROJECT}.raw.{table}"])

    def test_load_options_are_unchanged(self):
        for service in EXPECTED_TABLES:
            with self.subTest(service=service):
                (load,) = self.result(service)["loads"]
                self.assertEqual(load["write_disposition"], "WRITE_APPEND")
                self.assertEqual(load["schema_update_options"], ["ALLOW_FIELD_ADDITION", "ALLOW_FIELD_RELAXATION"])
                self.assertIn(load["autodetect"], (False, None))
                self.assertEqual(load["non_string_columns"], [], "raw tables are all-STRING")
                self.assertEqual(load["rows"], 2)

    def test_load_job_is_awaited_and_the_client_closed(self):
        for service in EXPECTED_TABLES:
            with self.subTest(service=service):
                result = self.result(service)
                self.assertEqual([load["result_calls"] for load in result["loads"]], [1])
                self.assertTrue(result["clients_closed"])

    def test_a_failed_load_job_raises_to_the_caller(self):
        for service in EXPECTED_TABLES:
            with self.subTest(service=service):
                result = self.result(service, "load_fails")
                self.assertEqual([load["result_calls"] for load in result["loads"]], [1])
                self.assertIsNotNone(result["exception"], "a failed load must not look like success")
                self.assertIn("load job failed", result["exception"])

    def test_no_key_file_is_read_and_no_dataset_is_created(self):
        for service in EXPECTED_TABLES:
            with self.subTest(service=service):
                for name in ("load", "load_fails"):
                    result = self.result(service, name)
                    self.assertEqual(result["key_file_reads"], [])
                    self.assertEqual(result["datasets_created"], [])
                    self.assertEqual(result["unexpected_writes"], [])


class MissingDataset(unittest.TestCase):
    META = {"cloud-run-meta-ads-reporting-a", "cloud-run-meta-ads-reporting-ecom"}

    def test_only_meta_creates_a_missing_raw_dataset_in_asia_southeast1(self):
        # Every other service just loads (BigQuery then fails if the dataset is missing); the two
        # Meta services create `raw` themselves, so a Meta run before the cutover creates the dataset
        for service in EXPECTED_TABLES:
            with self.subTest(service=service):
                result = RESULTS["default"][service]["load_dataset_missing"]
                expected = [f"{PROJECT}.raw@asia-southeast1"] if service in self.META else []
                self.assertEqual(result["datasets_created"], expected)

    def test_key_file_loads_at_import_are_only_in_known_services(self):
        # Some modules load a service-account key at import when a repo-root key exists (local
        # runs). The harness intercepts the call without reading the file; in the container the
        # path doesn't exist. Pin which services do it so a new one is noticed.
        loaders = {service for service, results in RESULTS["default"].items()
                   if results["load"]["import_key_file_reads"]}
        self.assertLessEqual(loaders, {"cloud-run-magento-order", "cloud-run-jushuitan-order"})


class Overrides(unittest.TestCase):
    def test_bq_raw_dataset_moves_the_28_standard_services(self):
        for service, table in EXPECTED_TABLES.items():
            if service in OWN_CONFIG:
                continue
            with self.subTest(service=service):
                (load,) = RESULTS["override"][service]["load"]["loads"]
                self.assertEqual(load["destination"], f"{PROJECT}.{OVERRIDE_DATASET}.{table}")

    def test_magento_reads_bq_project_bq_dataset_and_bq_table(self):
        (load,) = RESULTS["override"]["cloud-run-magento-order"]["load"]["loads"]
        self.assertEqual(load["destination"], "harness-project.harness_ds.harness_tbl")

    def test_surfosm_inventory_reads_bq_dataset_and_bq_table(self):
        (load,) = RESULTS["override"]["cloud-run-surfosm-inventory"]["load"]["loads"]
        self.assertEqual(load["destination"], f"{PROJECT}.harness_ds.harness_tbl")

    def test_bq_raw_dataset_does_not_move_magento_or_surfosm_inventory(self):
        for service, table in (("cloud-run-magento-order", "raw_magento_order"),
                               ("cloud-run-surfosm-inventory", "raw_surfosm_inventory")):
            with self.subTest(service=service):
                (load,) = RESULTS["ignored"][service]["load"]["loads"]
                self.assertEqual(load["destination"], f"{PROJECT}.raw.{table}")

    def test_project_comes_from_the_runtime_credentials_except_magento(self):
        for service, project in (("cloud-run-pancake-customer", "adc-runtime-project"),
                                 ("cloud-run-tiktok-thai-ads", "adc-runtime-project"),
                                 ("cloud-run-surfosm-inventory", "adc-runtime-project"),
                                 ("cloud-run-meta-ads-reporting-ecom", "adc-runtime-project"),
                                 ("cloud-run-magento-order", PROJECT)):  # BQ_PROJECT default wins
            with self.subTest(service=service):
                (load,) = RESULTS["other_adc_project"][service]["load"]["loads"]
                self.assertEqual(load["destination"].split(".")[0], project)


if __name__ == "__main__":
    unittest.main()
