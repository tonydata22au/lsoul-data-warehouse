"""Pagination and mid-run failures at the HTTP level (offline, mocked).

The HTTP client returns a scripted sequence of responses (auth calls included), so the
services' real fetch loops, transforms, routes and load paths run. A failure after some
pages were fetched must not turn into a partial load reported as success: the run must
end non-2xx (route) / non-zero (CLI) with no load job. Each service does its single load
after all fetching, so failing before the load is safe for a scheduler retry.

READINESS_BLOCKERS lists behaviour that still reports a failure as success and needs an
owner decision (tasks/raw-dataset-plan.md, decision 7); its tests would be expectedFailure.
It is empty since the 2026-11-06 deploy decisions (tasks/raw-dataset-deploy-plan.md):
D2 fixed the Surfosm detail skip, and D7 accepts partial loads on Jushuitan API codes (Dianplus no longer:
decision U5, 2026-11-07, tasks/raw-dataset-plan.md "Cutover execution"). Needs the services' requirements (see
tests/test_cloud_run_destinations.py for how to run).
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_run_harness as harness  # noqa: E402
from test_cloud_run_destinations import EXPECTED_TABLES, PROJECT  # noqa: E402

# Empty since 2026-11-06: decision D2 fixed the Surfosm detail skip (tasks/raw-dataset-deploy-plan.md).
READINESS_BLOCKERS = {}


def ok(body):
    return {"status": 200, "body": body}


HTTP_500 = {"status": 500, "body": {"error": "synthetic upstream failure"}}
CONN_RESET = {"error": "conn_error"}

# --- TikTok (VN and TH): code 0 + data.list + page_info ------------------------------------
TIKTOK = sorted(s for s in EXPECTED_TABLES if s.startswith("cloud-run-tiktok"))
_TT_ROW = harness._TIKTOK[0]


def tiktok_page(rows, total_page):
    return ok({"code": 0, "message": "OK",
               "data": {"list": rows, "page_info": {"page": 1, "total_page": total_page, "total_number": 2}}})


TIKTOK_API_ERROR = ok({"code": 40100, "message": "synthetic: requests are too frequent", "data": {}})

# --- Dianplus: auth, then pages until an empty results list ---------------------------------
DIANPLUS = sorted(s for s in EXPECTED_TABLES if s.startswith("cloud-run-dianplus"))
_DIAN_AUTH = ok({"resultCode": "success", "resultObject": "synthetic-token"})
_DIAN_ROW = {"id": "d1", "orderNo": "N1", "brandId": "b1", "createTime": "2026-11-05 01:00:00",
             "updateTime": "2026-11-05 01:00:00", "skuCode": "A"}


def dianplus_page(rows):
    return ok({"resultCode": "success", "resultObject": {"results": rows}})


DIANPLUS_API_ERROR = ok({"resultCode": "fail", "exceptionMessage": "synthetic: sign invalid"})

# --- Jushuitan: auth, then pages with has_next ----------------------------------------------
_JU_AUTH = ok({"code": 0, "data": {"access_token": "synthetic-token", "expires_in": 3600}})
_JU_ROW = {"o_id": 1, "so_id": "S1", "created": "2026-11-05 01:00:00", "modified": "2026-11-05 01:00:00",
           "items": [{"sku_id": "A", "qty": 1}]}


def jushuitan_page(rows, has_next):
    return ok({"code": 0, "data": {"orders": rows, "has_next": has_next}})


# --- Magento: auth (a JSON string), then pages with total_count -----------------------------
_MG_AUTH = ok("synthetic-token")
_MG_ROW = {"entity_id": 1, "increment_id": "100", "created_at": "2026-11-05 01:00:00",
           "updated_at": "2026-11-05 01:00:00", "items": [{"sku": "A", "qty_ordered": 1}]}


def magento_page(rows, total):
    return ok({"items": rows, "total_count": total})


# --- Surfosm order / order_return: order-number list, then one detail call per order --------
_T = "2026-11-05T01:00:00"


def surfosm_detail(number):
    return ok({"ok": True, "data": {"order_number": number, "ordered_at": _T, "status": "done",
                                    "order_items": [{"sku": "A", "quantity": 1}]}})


SURFOSM_LIST = ok({"data": {"order_numbers": ["SO1", "SO2"], "total_pages": 1, "has_next_page": False, "total": 2}})
SURFOSM_ARGV = ["--date", "2026-11-05"]


def route(service, name, pages, path="/"):
    return harness.scenario(service, name, action="route", http="pages", pages=pages, path=path)


def scenarios(service):
    if service in TIKTOK:
        p1, p2 = tiktok_page([_TT_ROW], 2), tiktok_page([dict(_TT_ROW, ad_id="2")], 2)
        return [
            route(service, "two_pages", [p1, p2]),
            route(service, "valid_empty", [tiktok_page([], 0)]),
            route(service, "page2_http_500", [p1, HTTP_500]),
            route(service, "page2_connection_reset", [p1, CONN_RESET]),
            route(service, "page2_api_error", [p1, TIKTOK_API_ERROR]),
        ]
    if service in DIANPLUS:
        p1, p2 = dianplus_page([_DIAN_ROW]), dianplus_page([dict(_DIAN_ROW, id="d2", orderNo="N2")])
        return [
            route(service, "two_pages", [_DIAN_AUTH, p1, p2, dianplus_page([])]),
            route(service, "valid_empty", [_DIAN_AUTH, dianplus_page([])]),
            route(service, "page2_http_500", [_DIAN_AUTH, p1, HTTP_500]),
            route(service, "page2_connection_reset", [_DIAN_AUTH, p1, CONN_RESET]),
            route(service, "page2_api_error", [_DIAN_AUTH, p1, DIANPLUS_API_ERROR]),
        ]
    if service == "cloud-run-jushuitan-order":
        p1 = jushuitan_page([_JU_ROW], True)
        return [
            route(service, "two_pages", [_JU_AUTH, p1, jushuitan_page([dict(_JU_ROW, o_id=2)], False)]),
            route(service, "valid_empty", [_JU_AUTH, jushuitan_page([], False)]),
            route(service, "page2_http_500", [_JU_AUTH, p1, HTTP_500]),  # repeated for every retry
            route(service, "page2_connection_reset", [_JU_AUTH, p1, CONN_RESET]),
            route(service, "page2_api_error", [_JU_AUTH, p1, ok({"code": 100, "msg": "synthetic: sign error"})]),
        ]
    if service == "cloud-run-magento-order":
        p1 = magento_page([_MG_ROW], 2)
        return [
            route(service, "two_pages", [_MG_AUTH, p1, magento_page([dict(_MG_ROW, entity_id=2)], 2)]),
            route(service, "valid_empty", [_MG_AUTH, magento_page([], 0)]),
            route(service, "page2_http_500", [_MG_AUTH, p1, HTTP_500]),
            route(service, "page2_connection_reset", [_MG_AUTH, p1, CONN_RESET]),
            route(service, "all_mode_http_500", [_MG_AUTH, HTTP_500], path="/?all=true"),
        ]
    if service == "cloud-run-pancake-customer":  # representative of the Pancake family
        row = {"id": 1, "inserted_at": _T, "updated_at": _T}
        p1 = ok({"data": [row], "total_pages": 2})
        return [
            route(service, "two_pages", [p1, ok({"data": [dict(row, id=2)], "total_pages": 2})]),
            route(service, "page2_http_500", [p1, HTTP_500]),
            route(service, "page2_connection_reset", [p1, CONN_RESET]),
        ]
    if service == "cloud-run-meta-ads-reporting-a":  # representative of the Meta family
        # Real paging.next URLs carry the access token, so a failed page-2 request must not echo it
        token = harness.CREDENTIAL_VALUES["META_ACCESS_TOKEN"]
        p1 = ok({"data": [{"date_start": "2026-11-05", "campaign_id": "1", "spend": "1"}],
                 "paging": {"next": f"https://graph.facebook.com/v24.0/synthetic-next?access_token={token}&after=x"}})
        return [
            route(service, "two_pages", [p1, ok({"data": [{"date_start": "2026-11-05", "campaign_id": "2", "spend": "2"}]})]),
            route(service, "page2_http_500", [p1, HTTP_500]),
            route(service, "page2_connection_reset", [p1, CONN_RESET]),
        ]
    if service == "cloud-run-surfosm-inventory":
        item = {"sku": "A", "warehouses": [{"warehouse_code": "W1"}]}
        p1 = ok({"data": {"as_of_date": "2026-11-05", "items": [item], "total_pages": 2, "has_next_page": True}})
        return [
            route(service, "two_pages", [p1, ok({"data": {"as_of_date": "2026-11-05", "items": [dict(item, sku="B")],
                                                          "total_pages": 2, "has_next_page": False}})]),
            route(service, "page2_http_500", [p1, HTTP_500]),
        ]
    if service in ("cloud-run-surfosm-order", "cloud-run-surfosm-order_return"):
        return [
            harness.scenario(service, "two_orders", action="cli", argv=SURFOSM_ARGV, http="pages",
                             pages=[SURFOSM_LIST, surfosm_detail("SO1"), surfosm_detail("SO2")]),
            harness.scenario(service, "second_detail_http_500", action="cli", argv=SURFOSM_ARGV, http="pages",
                             pages=[SURFOSM_LIST, surfosm_detail("SO1"), HTTP_500]),
            harness.scenario(service, "all_details_http_500", action="cli", argv=SURFOSM_ARGV, http="pages",
                             pages=[SURFOSM_LIST, HTTP_500]),
            harness.scenario(service, "detail_ok_false", action="cli", argv=SURFOSM_ARGV, http="pages",
                             pages=[SURFOSM_LIST, surfosm_detail("SO1"), ok({"ok": False, "error": "synthetic: not found"})]),
        ]
    return []


RESULTS = {}


def setUpModule():
    problem = harness.service_python_problem()
    if problem:
        raise unittest.SkipTest(problem)
    RESULTS.update({service: results for service, results in harness.run_all(scenarios).items() if results})


def is_2xx(status):
    return status is not None and 200 <= status < 300


class Base(unittest.TestCase):
    def result(self, service, name):
        result = RESULTS[service][name]
        self.assertNotIn("import_error", result, result.get("traceback"))
        self.assertIsNone(result["harness_abort"], result["harness_abort"])
        return result

    def assert_failed_without_load(self, result):
        if result["status"] is not None:
            self.assertFalse(is_2xx(result["status"]), (result["status"], result["body"]))
        else:
            self.assertNotEqual(result["exit_code"], 0, result["output_tail"][-300:])
        self.assertEqual(result["loads"], [], "a partial fetch must not be loaded")


class Pagination(Base):
    def test_all_pages_are_loaded_once(self):
        for service, results in RESULTS.items():
            with self.subTest(service=service):
                name = "two_orders" if "two_orders" in results else "two_pages"
                result = self.result(service, name)
                if result["status"] is not None:
                    self.assertTrue(is_2xx(result["status"]), (result["status"], result["body"]))
                else:
                    self.assertEqual(result["exit_code"], 0, result["exception"])
                (load,) = result["loads"]
                self.assertEqual(load["destination"], f"{PROJECT}.raw.{EXPECTED_TABLES[service]}")
                self.assertEqual(load["rows"], 2)

    def test_valid_empty_source_is_2xx_without_a_load(self):
        for service, results in RESULTS.items():
            if "valid_empty" not in results:
                continue
            with self.subTest(service=service):
                result = self.result(service, "valid_empty")
                self.assertTrue(is_2xx(result["status"]), (result["status"], result["body"]))
                self.assertEqual(result["loads"], [])


class MidRunFailure(Base):
    CASES = ("page2_http_500", "page2_connection_reset", "page2_api_error", "all_mode_http_500")
    # Decision D7/D8 (2026-11-06): a non-success Jushuitan API code ends the fetch and keeps the pages so far
    # (old behaviour, owner-approved); HTTP errors and connection failures still fail the run.
    # Decision U5 (2026-11-07): Dianplus no longer does. On 2026-11-07 its API rejected pageSize 2000 with a
    # non-success resultCode and the run answered 200 "0 entries", so a non-success code now fails the run.
    API_CODE_KEEPS_PAGES = frozenset({"cloud-run-jushuitan-order"})

    def test_a_failed_page_fails_the_run_and_loads_nothing(self):
        for service, results in RESULTS.items():
            for name in self.CASES:
                if name not in results or (name == "page2_api_error" and service in self.API_CODE_KEEPS_PAGES):
                    continue
                with self.subTest(service=service, case=name):
                    self.assert_failed_without_load(self.result(service, name))

    def test_dianplus_api_error_code_fails_the_run_and_loads_nothing(self):
        for service in DIANPLUS:
            with self.subTest(service=service):
                self.assert_failed_without_load(self.result(service, "page2_api_error"))

    def test_dianplus_requests_at_most_500_rows_per_page(self):
        # The Dianplus API answers "分页数不能超过500!" (page size can't exceed 500) above that.
        for service in DIANPLUS:
            with self.subTest(service=service):
                sizes = self.result(service, "two_pages")["page_sizes"]
                self.assertTrue(sizes, "no pageSize sent")
                self.assertTrue(all(0 < int(size) <= 500 for size in sizes), sizes)

    def test_jushuitan_api_error_code_keeps_the_pages_so_far(self):
        for service in sorted(self.API_CODE_KEEPS_PAGES):
            with self.subTest(service=service):
                result = self.result(service, "page2_api_error")
                self.assertTrue(is_2xx(result["status"]), (result["status"], result["body"]))
                self.assertEqual([load["rows"] for load in result["loads"]], [1])  # page 1 only

    def test_fetch_output_never_contains_a_credential(self):
        # Cloud Run keeps stdout/stderr in Cloud Logging, so a printed secret is a leaked secret.
        # Covers every log line and response body of the real fetch loops above (success and failure).
        for service, results in RESULTS.items():
            for name, result in results.items():
                with self.subTest(service=service, case=name):
                    self.assertEqual(result["credential_hits"], [], "credential printed or returned")

    def test_tiktok_vn_and_th_use_their_own_tables(self):
        for service in TIKTOK:
            with self.subTest(service=service):
                (load,) = self.result(service, "two_pages")["loads"]
                is_thai = "thai" in service
                self.assertEqual("_thai_" in load["destination"], is_thai)


class SurfosmOrderDetails(Base):
    """Decision D2 (2026-11-06): any failed order detail fails the run before the single load."""

    SERVICES = ("cloud-run-surfosm-order", "cloud-run-surfosm-order_return")

    def test_a_failed_order_detail_fails_the_run_and_loads_nothing(self):
        for service in self.SERVICES:
            for case in ("second_detail_http_500", "all_details_http_500", "detail_ok_false"):
                with self.subTest(service=service, case=case):
                    result = self.result(service, case)
                    self.assert_failed_without_load(result)
                    self.assertIn("Surfosm order detail", result["exception"] or "")  # the new raise, not a typo


class ReadinessBlockers(Base):
    """Required behaviour that is not met yet: kept as assertions, expected to fail."""

    def test_blocker_map_matches_the_expected_failures(self):
        blocked_tests = {name.removeprefix("test_blocked__") for name in dir(self) if name.startswith("test_blocked__")}
        self.assertEqual(blocked_tests, set(READINESS_BLOCKERS))
        for key, entry in READINESS_BLOCKERS.items():
            with self.subTest(blocker=key):
                self.assertIn(entry["service"], EXPECTED_TABLES)
                self.assertTrue(entry["behaviour"] and entry["decision"])


if __name__ == "__main__":
    unittest.main()
