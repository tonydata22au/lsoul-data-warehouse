"""Child process for tests/cloud_run_harness.py. Runs inside one Cloud Run service folder.

Never run by hand against real systems: it blocks sockets, disables dotenv, replaces
google.cloud.bigquery.Client with a recording fake, stubs the HTTP client and the
service-account key loaders, then imports the service through its app_runner.py
(the way gunicorn does) and runs the requested scenarios. Results go to a JSON file.

Usage (by the harness only): python -B cloud_run_harness_child.py <request.json> <result.json>
"""

import copy
import importlib.util
import io
import json
import logging
import os
import socket
import sys
import time
import traceback
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from urllib.parse import urlparse


def _blocked(*args, **kwargs):
    raise OSError("network disabled by the test harness")


socket.socket.connect = socket.socket.connect_ex = _blocked
socket.create_connection = socket.getaddrinfo = _blocked

import dotenv  # noqa: E402
import dotenv.main  # noqa: E402

dotenv.load_dotenv = dotenv.main.load_dotenv = lambda *args, **kwargs: False

import google.auth  # noqa: E402
import pandas as pd  # noqa: E402
import requests  # noqa: E402
from google.api_core import exceptions as gexc  # noqa: E402
from google.auth.credentials import AnonymousCredentials  # noqa: E402
from google.cloud import bigquery  # noqa: E402
from google.oauth2 import service_account  # noqa: E402

REQUEST = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
ADC_PROJECT = REQUEST.get("adc_project", "marine-cycle-484213-b4")
HTTP_CALL_LIMIT = 200


class HarnessAbort(BaseException):
    """Raised past `except Exception` handlers when a service loops on a failing call."""


STATE = {}


def reset_state(scenario):
    STATE.clear()
    STATE.update(
        scenario=scenario,
        loads=[],
        http_calls=[],
        key_file_reads=[],
        datasets_created=[],
        unexpected_writes=[],
        clients=[],
        sleep_calls=0,
    )


# --- credentials: never read a real key file -------------------------------------------------

def _no_key_file(*args, **kwargs):
    STATE["key_file_reads"].append(str(args[0]) if args else "<info>")
    return AnonymousCredentials()


service_account.Credentials.from_service_account_file = staticmethod(_no_key_file)
service_account.Credentials.from_service_account_info = staticmethod(_no_key_file)
google.auth.default = lambda *args, **kwargs: (AnonymousCredentials(), ADC_PROJECT)

# --- time: retry loops must not sleep ---------------------------------------------------------


def _no_sleep(seconds=0):
    STATE["sleep_calls"] += 1


time.sleep = _no_sleep

# --- BigQuery: a recording fake client ---------------------------------------------------------


class FakeLoadJob:
    def __init__(self, record, fail):
        self._record = record
        self._fail = fail
        self.job_id = f"harness-load-{len(STATE['loads'])}"
        self.output_rows = record["rows"]
        self.errors = None
        self.state = "PENDING"

    def result(self, *args, **kwargs):
        self._record["result_calls"] += 1
        if self._fail:
            self.state = "DONE"
            self.errors = [{"reason": "invalid", "message": "harness: load job failed"}]
            raise gexc.BadRequest("harness: load job failed")
        self.state = "DONE"
        return self

    def done(self, *args, **kwargs):
        return self.state == "DONE"


def _destination(table_ref, default_project):
    if isinstance(table_ref, str):
        parts = table_ref.replace(":", ".").split(".")
        if len(parts) == 2:
            parts = [default_project] + parts
        return ".".join(parts)
    if isinstance(table_ref, bigquery.Table):
        table_ref = table_ref.reference
    return f"{table_ref.project}.{table_ref.dataset_id}.{table_ref.table_id}"


def _enum_text(value):
    return getattr(value, "value", value)


class FakeClient:
    def __init__(self, project=None, credentials=None, location=None, **kwargs):
        self.project = project or ADC_PROJECT
        self.location = location
        STATE["clients"].append({"project_arg": project, "closed": False})
        self._index = len(STATE["clients"]) - 1

    def dataset(self, dataset_id, project=None):
        return bigquery.DatasetReference(project or self.project, dataset_id)

    def get_dataset(self, dataset_ref, *args, **kwargs):
        if isinstance(dataset_ref, str):
            dataset_ref = bigquery.DatasetReference.from_string(dataset_ref, default_project=self.project)
        if STATE["scenario"].get("dataset_missing"):
            raise gexc.NotFound(f"harness: dataset {dataset_ref.dataset_id} not found")
        return bigquery.Dataset(dataset_ref)

    def create_dataset(self, dataset, *args, **kwargs):
        ref = dataset.reference if isinstance(dataset, bigquery.Dataset) else dataset
        location = getattr(dataset, "location", None)
        STATE["datasets_created"].append(f"{ref.project}.{ref.dataset_id}@{location}")
        return dataset

    def get_table(self, table_ref, *args, **kwargs):
        if isinstance(table_ref, str):
            table_ref = bigquery.TableReference.from_string(table_ref, default_project=self.project)
        return bigquery.Table(table_ref)

    def load_table_from_dataframe(self, dataframe, destination, job_config=None, **kwargs):
        config = job_config or bigquery.LoadJobConfig()
        record = {
            "destination": _destination(destination, self.project),
            "rows": int(len(dataframe)),
            "columns": [str(c) for c in dataframe.columns],
            "write_disposition": _enum_text(config.write_disposition),
            "schema_update_options": sorted(_enum_text(o) for o in (config.schema_update_options or [])),
            "autodetect": config.autodetect,
            "non_string_columns": sorted(
                str(c) for c, dtype in dataframe.dtypes.items()
                if not (pd.api.types.is_object_dtype(dtype) or pd.api.types.is_string_dtype(dtype))
            ),
            "result_calls": 0,
        }
        STATE["loads"].append(record)
        return FakeLoadJob(record, fail=STATE["scenario"].get("load_error", False))

    def _unexpected(self, name):
        def call(*args, **kwargs):
            STATE["unexpected_writes"].append(name)
            raise AssertionError(f"harness: unexpected BigQuery call {name}")
        return call

    def __getattr__(self, name):
        if name in {"load_table_from_json", "load_table_from_uri", "load_table_from_file",
                    "insert_rows", "insert_rows_json", "insert_rows_from_dataframe", "query",
                    "delete_table", "create_table", "update_table", "copy_table"}:
            return self._unexpected(name)
        raise AttributeError(name)

    def close(self):
        STATE["clients"][self._index]["closed"] = True


bigquery.Client = FakeClient

# --- HTTP: every request goes through requests.Session.request ---------------------------------

_JSON_HEADERS = {"Content-Type": "application/json"}


def _response(url, status, body):
    response = requests.Response()
    response.status_code = status
    response.url = url
    response.headers.update(_JSON_HEADERS)
    response._content = json.dumps(body).encode()
    response.encoding = "utf-8"
    return response


def _full_url(method, url, kwargs):
    """The URL requests would send, query string included (it appears in real error messages)."""
    try:
        return requests.Request(method, url, params=kwargs.get("params")).prepare().url
    except Exception:
        return url


def _connection_error(full_url):
    # Same shape as urllib3's message, which carries the path and query string
    parts = urlparse(full_url)
    path = parts.path + (f"?{parts.query}" if parts.query else "")
    return requests.exceptions.ConnectionError(
        f"HTTPSConnectionPool(host='{parts.netloc}', port=443): Max retries exceeded with url: {path} "
        "(Caused by NewConnectionError('harness: network unavailable'))")


def fake_request(self, method, url, *args, **kwargs):
    full_url = _full_url(method, url, kwargs)
    STATE["http_calls"].append({"method": method.upper(), "host": urlparse(url).netloc,
                                "path": urlparse(url).path})
    if len(STATE["http_calls"]) > HTTP_CALL_LIMIT:
        raise HarnessAbort(f"more than {HTTP_CALL_LIMIT} HTTP calls (retry loop?)")
    http = STATE["scenario"].get("http", "unexpected")
    if http == "conn_error":
        raise _connection_error(full_url)
    if http == "http_500":
        return _response(full_url, 500, {"error": "harness: upstream error", "code": 500})
    if http == "pages":
        # The Nth HTTP call (auth included) gets pages[N]; calls past the end repeat the last page
        pages = STATE["scenario"]["pages"]
        index = len(STATE["http_calls"]) - 1
        page = pages[index] if index < len(pages) else pages[-1]
        if page.get("error") == "conn_error":
            raise _connection_error(full_url)
        return _response(full_url, page.get("status", 200), page.get("body", {}))
    raise HarnessAbort(f"unexpected HTTP call {method} {urlparse(url).netloc}{urlparse(url).path}")


requests.sessions.Session.request = fake_request

# --- service import, the gunicorn way ----------------------------------------------------------


def import_service():
    runner_path = Path.cwd() / "app_runner.py"
    spec = importlib.util.spec_from_file_location(f"app_runner_{len(IMPORTS)}", runner_path)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    IMPORTS.append(runner)
    return runner, runner.module


IMPORTS = []


def _stub(value_spec):
    kind = value_spec.get("as", "value")
    value = value_spec.get("value")

    def stub(*args, **kwargs):
        if value_spec.get("raise"):
            raise ValueError(value_spec["raise"])
        if kind == "dataframe":
            return pd.DataFrame(copy.deepcopy(value))
        if kind == "tuple_df":
            return (pd.DataFrame(copy.deepcopy(value[0])),) + tuple(copy.deepcopy(value[1:]))
        return copy.deepcopy(value)

    return stub


def run_scenario(module, app, scenario):
    full_body = ""
    out = {"name": scenario["name"], "status": None, "body": None, "exit_code": None,
           "exception": None, "returned": None, "harness_abort": None}
    for name, value_spec in (scenario.get("stubs") or {}).items():
        setattr(module, name, _stub(value_spec))
    for name, value in (scenario.get("set_attrs") or {}).items():
        setattr(module, name, value)
    for name, value in (scenario.get("set_paths") or {}).items():
        setattr(module, name, Path(value))
    action = scenario["action"]
    stdout = io.StringIO()
    # Also capture logging records (handlers bound to the real stderr at import time are bypassed);
    # the root level stays whatever the service configured, as it would be on Cloud Run
    log_capture = logging.StreamHandler(stdout)
    logging.getLogger().addHandler(log_capture)
    try:
        with redirect_stdout(stdout), redirect_stderr(stdout):
            if action == "route":
                client = app.test_client()
                response = client.open(scenario.get("path", "/"), method=scenario.get("method", "GET"))
                out["status"] = response.status_code
                full_body = response.get_data(as_text=True)
                out["body"] = full_body[:400]
            elif action == "cli":
                if not hasattr(module, "main"):
                    out["exception"] = "NoCLI: module has no main()"
                else:
                    saved_argv = sys.argv
                    sys.argv = ["service"] + scenario.get("argv", [])
                    try:
                        module.main()
                        out["exit_code"] = 0
                    except SystemExit as exc:
                        code = exc.code
                        out["exit_code"] = code if isinstance(code, int) else (0 if code is None else 1)
                    finally:
                        sys.argv = saved_argv
            elif action == "call":
                func = getattr(module, scenario["function"])
                args = [pd.DataFrame(scenario["dataframe"])] if "dataframe" in scenario else []
                args += [getattr(module, a[1:]) if isinstance(a, str) and a.startswith("@") else a
                         for a in scenario.get("args", [])]
                returned = func(*args, **scenario.get("kwargs", {}))
                out["returned"] = repr(returned)[:200]
            elif action == "attrs":
                out["returned"] = {name: repr(getattr(module, name, "<missing>")) for name in scenario["names"]}
            else:
                raise ValueError(f"unknown action {action}")
    except HarnessAbort as exc:
        out["harness_abort"] = str(exc)
    except SystemExit as exc:
        out["exit_code"] = exc.code if isinstance(exc.code, int) else 1
    except Exception as exc:  # the service raised: record it
        out["exception"] = f"{type(exc).__name__}: {str(exc)[:300]}"
        if action == "cli":
            out["exit_code"] = 1  # an uncaught exception ends the interpreter with status 1
    finally:
        logging.getLogger().removeHandler(log_capture)
    out.update({k: STATE[k] for k in ("loads", "datasets_created", "unexpected_writes",
                                       "key_file_reads", "sleep_calls")})
    out["http_calls"] = len(STATE["http_calls"])
    out["http_hosts"] = sorted({c["host"] for c in STATE["http_calls"]})
    out["clients_closed"] = all(c["closed"] for c in STATE["clients"]) if STATE["clients"] else None
    full_output = stdout.getvalue()
    out["output_tail"] = full_output[-1500:]
    # Scan the whole output, the full body and the raised exception text for any credential value
    scanned = full_output + full_body + (out["exception"] or "")
    out["credential_hits"] = sorted(
        name for name in REQUEST.get("credential_names", [])
        if os.environ.get(name) and os.environ[name] in scanned
    )
    return out


def main():
    results = []
    for scenario in REQUEST["scenarios"]:
        reset_state(scenario)
        try:
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                runner, module = import_service()
        except BaseException as exc:  # import failure is itself a result
            results.append({"name": scenario["name"], "import_error":
                            f"{type(exc).__name__}: {exc}", "traceback": traceback.format_exc()[-1500:]})
            continue
        app = runner.app
        app.config["TESTING"] = False  # exercise the service's own error handling, not Flask's
        app.config["PROPAGATE_EXCEPTIONS"] = False
        import_key_file_reads = list(STATE["key_file_reads"])  # intercepted at import, never read
        reset_state(scenario)
        result = run_scenario(module, app, scenario)
        result["import_key_file_reads"] = import_key_file_reads
        results.append(result)
    Path(sys.argv[2]).write_text(json.dumps(results, indent=1, default=str), encoding="utf-8")


if __name__ == "__main__":
    main()
