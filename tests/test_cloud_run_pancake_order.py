"""Unit tests for src/cloud_run/cloud-run-pancake-order (offline: no network, no .env, no BigQuery).

Run with the service's dependencies installed, for example:
    .venv/bin/python -m unittest tests.test_cloud_run_pancake_order
Skipped on Python < 3.11 or when pandas, Flask or google-cloud-bigquery are missing.
"""

import importlib.util
import json
import logging
import os
import sys
import types
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

SERVICE_FILE = (
    Path(__file__).resolve().parents[1]
    / "src"
    / "cloud_run"
    / "cloud-run-pancake-order"
    / "cr-pancake-order.py"
)
FAKE_KEY = "TESTKEY0123456789"

svc = None
pd = None
requests = None
_patches = []


def setUpModule():
    global svc, pd, requests
    # `python3 -m unittest discover -s tests` may run on an older system Python (3.9 on macOS)
    if sys.version_info < (3, 11):  # noqa: UP036
        raise unittest.SkipTest("the service targets Python 3.13")
    try:
        import flask  # noqa: F401
        import google.cloud.bigquery  # noqa: F401
        import pandas
        import requests as requests_module
    except ImportError as exc:
        raise unittest.SkipTest(f"service dependencies not installed: {exc}") from None
    pd, requests = pandas, requests_module

    # Never read the repo .env, never reach the network, never touch the real key file
    no_dotenv = types.SimpleNamespace(load_dotenv=lambda *args, **kwargs: None)
    root = logging.getLogger()
    saved_handlers, saved_level = root.handlers[:], root.level
    with (
        mock.patch.dict(sys.modules, {"dotenv": no_dotenv}),
        mock.patch.dict(os.environ, {}, clear=False),
    ):
        os.environ.pop("K_SERVICE", None)
        spec = importlib.util.spec_from_file_location("cr_pancake_order_under_test", SERVICE_FILE)
        svc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(svc)
    root.handlers[:], root.level = saved_handlers, saved_level  # undo configure_logging()
    svc.logger.disabled = True
    svc.SERVICE_ACCOUNT_FILE = Path("/nonexistent/google-credentials.json")

    for patcher in (
        mock.patch("socket.socket.connect", side_effect=OSError("network disabled in tests")),
        mock.patch.dict(os.environ, {"PANCAKE_API_KEY": FAKE_KEY}),
    ):
        patcher.start()
        _patches.append(patcher)


def tearDownModule():
    for patcher in reversed(_patches):
        patcher.stop()


def make_order(order_id, **fields):
    order = {
        "id": order_id,
        "system_id": 1,
        "status": 3,
        "inserted_at": "2026-10-23T03:15:30",
        "updated_at": "2026-10-23T05:00:00",
        "received_at_shop": False,
        "tags": [],
        "note": None,
        "customer": {"customer_id": f"c{order_id}", "gender": "female"},
        "items": [{"id": 1, "is_wholesale": False, "variation_info": {"name": "Shirt"}}],
    }
    order.update(fields)
    return order


def fake_session(pages):
    """A requests.Session stand-in that serves pages[page - 1] and records each call's params."""
    calls = []

    def get(url, params=None, timeout=None):
        calls.append(dict(params))
        response = requests.Response()
        response.status_code = 200
        page = params["page"]
        body = pages[page - 1] if page <= len(pages) else {"data": []}
        response._content = json.dumps(body).encode()
        return response

    session = mock.MagicMock()
    session.__enter__.return_value.get.side_effect = get
    return session, calls


class DateWindow(unittest.TestCase):
    # 00:30 in Vietnam is still the previous day in UTC: the window must follow Vietnam time
    NOW = datetime(2026, 10, 24, 0, 30)

    def setUp(self):
        self.now = self.NOW.replace(tzinfo=svc.VIETNAM_TZ)

    def test_default_is_yesterday(self):
        self.assertEqual(
            svc.resolve_window(now=self.now), ("2026-10-23T00:00:00", "2026-10-23T23:59:59")
        )

    def test_all_is_capped_at_yesterday(self):
        self.assertEqual(
            svc.resolve_window(all_flag=True, now=self.now), (None, "2026-10-23T23:59:59")
        )

    def test_last_30_days(self):
        self.assertEqual(
            svc.resolve_window(last_30_days=True, now=self.now),
            ("2026-09-24T00:00:00", "2026-10-23T23:59:59"),
        )

    def test_explicit_dates_win(self):
        window = svc.resolve_window(
            start_date="2026-10-01T00:00:00", last_30_days=True, now=self.now
        )
        self.assertEqual(window, ("2026-10-01T00:00:00", None))

    def test_parse_date_to_unix(self):
        self.assertEqual(svc.parse_date_to_unix("2026-10-23T00:00:00"), 1792688400)  # 17:00 UTC
        self.assertIsNone(svc.parse_date_to_unix(None))
        self.assertIsNone(svc.parse_date_to_unix("  "))
        with self.assertRaisesRegex(ValueError, "Expected format"):
            svc.parse_date_to_unix("2026-10-23")


class LoadData(unittest.TestCase):
    def fetch(self, pages, **kwargs):
        session, calls = fake_session(pages)
        with mock.patch.object(svc.requests, "Session", return_value=session):
            return svc.load_data(**kwargs), calls

    def test_follows_pages_until_a_short_last_page(self):
        pages = [
            {"data": [{"id": str(i)} for i in range(1000)], "total_pages": 2},
            {"data": [{"id": "last"}], "total_pages": 2},
        ]
        orders, calls = self.fetch(
            pages, start_date="2026-10-23T00:00:00", end_date="2026-10-23T23:59:59"
        )
        self.assertEqual(len(orders), 1001)
        self.assertEqual([call["page"] for call in calls], [1, 2])
        self.assertEqual(
            calls[0],
            {
                "api_key": FAKE_KEY,
                "page": 1,
                "page_size": 1000,
                "updateStatus": "updated_at",
                "startDateTime": 1792688400,
                "endDateTime": 1792774799,
            },
        )

    def test_max_pages_stops_early(self):
        full_page = {"data": [{"id": str(i)} for i in range(1000)], "total_pages": 9}
        orders, calls = self.fetch([full_page] * 9, max_pages=1)
        self.assertEqual((len(orders), len(calls)), (1000, 1))

    def test_errors_never_contain_the_api_key(self):
        def fail(url, params=None, timeout=None):
            raise requests.exceptions.ConnectionError(
                f"Max retries exceeded with url: /orders?api_key={params['api_key']}&page=1"
            )

        session = mock.MagicMock()
        session.__enter__.return_value.get.side_effect = fail
        with mock.patch.object(svc.requests, "Session", return_value=session):
            with self.assertRaises(ValueError) as caught:
                svc.load_data()
        self.assertNotIn(FAKE_KEY, str(caught.exception))
        self.assertIn("api_key=***", str(caught.exception))
        self.assertTrue(caught.exception.__suppress_context__)  # original error not chained


class Transform(unittest.TestCase):
    def transform(self, orders):
        df = svc.flatten_data(orders)
        df = svc.rename_and_reorder_columns(df)
        df = svc.convert_booleans_to_binary(df)
        df = svc.convert_dates_to_timestamp(df)
        return svc.clean_empty_json(df)

    def test_one_row_per_item_in_map_order(self):
        two_items = [
            {"id": 1, "is_wholesale": False, "variation_info": {"name": "Shirt"}},
            {"id": 2, "is_wholesale": True, "variation_info": {"name": "Skirt"}},
        ]
        tagged = [{"id": 5, "name": "VIP"}]
        orders = [make_order("1001", items=two_items), make_order("1002", tags=tagged)]
        df = self.transform(orders)

        self.assertEqual(df["order_id"].tolist(), ["1001", "1001", "1002"])
        mapped = [column for column in svc.COLUMN_RENAME_MAP.values() if column in df.columns]
        self.assertEqual(list(df.columns), mapped)
        self.assertEqual(df["product_name"].tolist(), ["Shirt", "Skirt", "Shirt"])
        self.assertEqual(df["is_wholesale"].tolist(), [0, 1, 0])
        # 03:15:30 UTC from the API is 10:15:30 in Vietnam
        self.assertEqual(set(df["inserted_at"]), {"20261023101530"})
        self.assertEqual(df["tags"].tolist()[:2], ["", ""])  # empty list -> ""

    def test_meta_fields_cover_every_order_level_column(self):
        order_keys = [key for key in svc.COLUMN_RENAME_MAP if not key.startswith("item_")]
        meta = [".".join(f) if isinstance(f, list) else f for f in svc.ORDER_META_FIELDS]
        self.assertEqual(meta, order_keys)
        self.assertIn(["customer", "gender"], svc.ORDER_META_FIELDS)


class LoadToBigQuery(unittest.TestCase):
    def test_appends_strings_with_field_addition(self):
        df = pd.DataFrame({"order_id": ["1", "1"], "total_price": [10.0, float("nan")]})
        with mock.patch.object(svc.bigquery, "Client") as client_cls:
            client = client_cls.return_value
            client.project = "test-project"
            client.load_table_from_dataframe.return_value = mock.Mock(output_rows=2, job_id="job-1")
            message = svc.insert_to_bigquery(df)

        self.assertIsNone(client_cls.call_args.kwargs["credentials"])  # no key file -> ADC
        (sent, table_ref), kwargs = client.load_table_from_dataframe.call_args
        self.assertEqual(str(table_ref), "test-project.raw_pancake.raw_order")
        config = kwargs["job_config"]
        self.assertEqual(config.write_disposition, "WRITE_APPEND")
        self.assertEqual(
            config.schema_update_options, ["ALLOW_FIELD_RELAXATION", "ALLOW_FIELD_ADDITION"]
        )
        self.assertEqual(sent["total_price"].iloc[0], "10.0")
        # Missing values load as "" (pandas 2) or NULL (pandas 3); never as the text "nan"
        self.assertTrue(pd.isna(sent["total_price"].iloc[1]) or sent["total_price"].iloc[1] == "")
        self.assertTrue(client.close.called)
        self.assertIn("Unique entries: 1", message)


class HttpRoute(unittest.TestCase):
    def setUp(self):
        self.client = svc.app.test_client()

    def request(self, method, url):
        with mock.patch.object(svc, "run_export", return_value=("ok", 200)) as export:
            response = getattr(self.client, method)(url)
        return response, export

    def test_get_and_post_run_the_default_window(self):
        for method in ("get", "post"):
            with self.subTest(method=method):
                response, export = self.request(method, "/")
                self.assertEqual(response.status_code, 200)
                export.assert_called_once_with(start_date=None, end_date=None)

    def test_backfill_window(self):
        response, export = self.request(
            "get", "/?start_date=2026-10-01T00:00:00&end_date=2026-10-01T23:59:59"
        )
        self.assertEqual(response.status_code, 200)
        export.assert_called_once_with(
            start_date="2026-10-01T00:00:00", end_date="2026-10-01T23:59:59"
        )

    def test_bad_date_is_rejected_before_running(self):
        response, export = self.request("get", "/?start_date=2026-10-01")
        self.assertEqual(response.status_code, 400)
        export.assert_not_called()

    def test_other_methods_are_not_allowed(self):
        self.assertEqual(self.request("put", "/")[0].status_code, 405)

    def test_failure_returns_500(self):
        with mock.patch.object(svc, "run_export", side_effect=ValueError("API request failed")):
            response = self.client.post("/")
        self.assertEqual(response.status_code, 500)
        self.assertIn("API request failed", response.get_data(as_text=True))


class CloudLogging(unittest.TestCase):
    def test_json_lines_carry_severity_and_traceback(self):
        try:
            raise RuntimeError("boom")
        except RuntimeError:
            record = logging.LogRecord(
                "pancake_order",
                logging.ERROR,
                __file__,
                1,
                "Export %s",
                ("failed",),
                sys.exc_info(),
            )
        entry = json.loads(svc.CloudLoggingFormatter().format(record))
        self.assertEqual(entry["severity"], "ERROR")
        self.assertTrue(entry["message"].startswith("Export failed\nTraceback"))
        self.assertIn("RuntimeError: boom", entry["message"])


if __name__ == "__main__":
    unittest.main()
