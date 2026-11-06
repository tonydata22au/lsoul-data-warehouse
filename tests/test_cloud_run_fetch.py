"""Pagination and mid-run failures at the HTTP level (offline, mocked).

The HTTP client returns a scripted sequence of responses (auth calls included), so the
services' real fetch loops, transforms, routes and load paths run. A failure after some
pages were fetched must not turn into a partial load reported as success: the run must
end non-2xx (route) / non-zero (CLI) with no load job. Each service does its single load
after all fetching, so failing before the load is safe for a scheduler retry.

READINESS_BLOCKERS lists behaviour that still reports a failure as success and needs an
owner decision (tasks/raw-dataset-plan.md, decision 7). Its tests keep asserting the
required behaviour and are marked expectedFailure; while the map is non-empty the local
readiness verdict is NOT READY. Needs the services' requirements (see
tests/test_cloud_run_destinations.py for how to run).
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_run_harness as harness  # noqa: E402
from test_cloud_run_destinations import EXPECTED_TABLES, PROJECT  # noqa: E402

READINESS_BLOCKERS = {
    "surfosm_order_detail_skip": {
        "service": "cloud-run-surfosm-order",
        "behaviour": "fetch_order_details() logs a warning and skips every order whose detail request "
                     "fails or answers ok:false (cr-surfosm-order.py:196-208), then loads the remaining "
                     "orders and reports success (HTTP 200 / exit 0). If every detail fails it reports "
                     "'0 order details found' with 200 / exit 0, which looks like a valid empty day.",
        "decision": "Should one failed order detail fail the whole run (no load, non-2xx, scheduler "
                    "retry) or be skipped with an explicit partial status and alert? The default "
                    "31-day window re-fetches old dates, which may heal a skip but appends duplicates.",
    },
    "surfosm_order_return_detail_skip": {
        "service": "cloud-run-surfosm-order_return",
        "behaviour": "Same as cloud-run-surfosm-order (cr-surfosm-order_return.py:170-182).",
        "decision": "Same decision as surfosm_order_detail_skip; keep both services consistent.",
    },
}


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
        p1 = ok({"data": [{"date_start": "2026-11-05", "campaign_id": "1", "spend": "1"}],
                 "paging": {"next": "https://graph.facebook.com/v24.0/synthetic-next"}})
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

    def test_a_failed_page_fails_the_run_and_loads_nothing(self):
        for service, results in RESULTS.items():
            for name in self.CASES:
                if name not in results:
                    continue
                with self.subTest(service=service, case=name):
                    self.assert_failed_without_load(self.result(service, name))

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


class ReadinessBlockers(Base):
    """Required behaviour that is not met yet: kept as assertions, expected to fail."""

    BLOCKED_SERVICES = ("cloud-run-surfosm-order", "cloud-run-surfosm-order_return")

    @unittest.expectedFailure
    def test_blocked__surfosm_order_detail_skip(self):
        self.assert_failed_without_load(self.result("cloud-run-surfosm-order", "second_detail_http_500"))

    @unittest.expectedFailure
    def test_blocked__surfosm_order_return_detail_skip(self):
        self.assert_failed_without_load(self.result("cloud-run-surfosm-order_return", "second_detail_http_500"))

    def test_blocked_behaviour_is_still_exactly_the_documented_one(self):
        # Pins today's behaviour, so each expectedFailure above fails for the documented reason
        # (and not, say, a broken fixture). When a blocker is fixed this test must change with it.
        for service in self.BLOCKED_SERVICES:
            with self.subTest(service=service, case="one detail fails"):
                partial = self.result(service, "second_detail_http_500")
                self.assertEqual(partial["exit_code"], 0)
                self.assertEqual([load["rows"] for load in partial["loads"]], [1])  # SO1 loaded, SO2 skipped
                self.assertIn("Warning: Failed to fetch order", partial["output_tail"])
            with self.subTest(service=service, case="every detail fails"):
                silent = self.result(service, "all_details_http_500")
                self.assertEqual(silent["exit_code"], 0)
                self.assertEqual(silent["loads"], [])
                self.assertIn("0 order details found", silent["output_tail"])

    def test_blocker_map_matches_the_expected_failures(self):
        blocked_tests = {name.removeprefix("test_blocked__") for name in dir(self) if name.startswith("test_blocked__")}
        self.assertEqual(blocked_tests, set(READINESS_BLOCKERS))
        for key, entry in READINESS_BLOCKERS.items():
            with self.subTest(blocker=key):
                self.assertIn(entry["service"], EXPECTED_TABLES)
                self.assertTrue(entry["behaviour"] and entry["decision"])


if __name__ == "__main__":
    unittest.main()
