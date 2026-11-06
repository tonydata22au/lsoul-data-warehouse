"""Run Cloud Run service scenarios in isolated subprocesses (offline; no network, no BigQuery).

Each call starts tests/cloud_run_harness_child.py inside one service folder with:
- a minimal environment: temporary HOME/CLOUDSDK_CONFIG (no ADC files), dummy values for
  every credential variable, no GOOGLE_APPLICATION_CREDENTIALS, plus the case's overrides;
- dotenv disabled, sockets blocked, a recording fake bigquery.Client, stubbed HTTP and
  service-account key loaders (see the child's docstring).

The service interpreter defaults to the current one. Point LSOUL_SERVICE_PYTHON at an
environment with the services' requirements to run these tests from a bare Python.
"""

import json
import os
import subprocess
import sys
import tempfile
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLOUD_RUN = ROOT / "src" / "cloud_run"
CHILD = Path(__file__).resolve().with_name("cloud_run_harness_child.py")
SERVICE_PYTHON = os.environ.get("LSOUL_SERVICE_PYTHON", sys.executable)

sys.path.insert(0, str(ROOT / "scripts"))
from validate_repo import CREDENTIAL_ENV_VARS  # noqa: E402

REQUIRED_MODULES = ("flask", "pandas", "pyarrow", "requests", "pytz", "dotenv", "google.cloud.bigquery")

# A distinct synthetic value per credential variable, so a test can tell which one leaked into
# a log line or a response body
CREDENTIAL_VALUES = {name: f"harness-{name.lower().replace('_', '-')}-value" for name in CREDENTIAL_ENV_VARS}

# --- Synthetic inputs (never expected outputs) ------------------------------------------------
# Small records shaped like each API's payload, just enough to pass the service's own
# transforms so the run reaches its BigQuery load. No real customer or business data.

_T = "2026-11-05T01:00:00"
_PANCAKE = [{"id": 101, "inserted_at": _T, "updated_at": _T, "name": "Synthetic shirt", "customer": {"id": "c1"}}]
_PANCAKE_PRODUCT_ROWS = [{"id": 101, "inserted_at": _T, "updated_at": _T, "product": [{"id": "p1", "remain_quantity": 3}]}]
_DIANPLUS = [{"id": "d1", "createTime": "2026-11-05 01:00:00", "updateTime": "2026-11-05 01:00:00"}]
_TIKTOK = [{"dimensions": {"ad_id": "1", "stat_time_day": "2026-11-05 00:00:00"}, "metrics": {"spend": "1.5"},
            "ad_id": "1", "create_time": "2026-11-05 01:00:00", "modify_time": "2026-11-05 01:00:00"}]
_META = [{"date_start": "2026-11-05", "date_stop": "2026-11-05", "campaign_id": "1", "spend": "1",
          "actions": [{"action_type": "purchase", "value": "2"}]}]
_SURFOSM_ORDER = [{"order_number": "SO1", "parameter_date": "2026-11-05", "ordered_at": _T, "status": "done",
                   "order_items": [{"sku": "A", "quantity": 1}]}]


def _list(value):
    return {"value": value}


def _frame(records):
    return {"as": "dataframe", "value": records}


def fetch_stubs(service, empty=False):
    """Replace only the service's fetch function(s); transforms and the load path stay real."""
    short = service.replace("cloud-run-", "")
    if short.startswith("dianplus"):
        return {"load_data": _frame([] if empty else _DIANPLUS)}
    if short == "jushuitan-order":
        rows = [{"o_id": "1", "created": "2026-11-05 01:00:00", "modified": "2026-11-05 01:00:00"}]
        return {"load_data": _frame([] if empty else rows)}
    if short == "magento-order":
        orders = [{"entity_id": 1, "increment_id": "100", "created_at": "2026-11-05 01:00:00",
                   "updated_at": "2026-11-05 01:00:00", "items": [{"sku": "A", "qty_ordered": 1}]}]
        return {"get_auth_access_token": _list("synthetic-token"), "_fetch_pages": _list([] if empty else orders)}
    if short.startswith("meta-ads"):
        return {"fetch_insights": _list([] if empty else _META)}
    if short == "surfosm-inventory":
        items = [{"as_of_date": "2026-11-05", "sku": "A", "barcode": "B1", "product_name": "Synthetic",
                  "warehouses": [{"warehouse_code": "W1", "stock": {"on_hand": 1}}]}]
        return {"fetch_inventory": _list([] if empty else items)}
    if short in ("surfosm-order", "surfosm-order_return"):
        return {"load_data_url_1": _list([] if empty else ["SO1"]),
                "fetch_order_details": _list([] if empty else _SURFOSM_ORDER)}
    if short == "pancake-stats_inventory_product":
        return {"load_data": _list([] if empty else _PANCAKE_PRODUCT_ROWS)}
    if short.startswith("pancake"):
        return {"load_data": _list([] if empty else _PANCAKE)}
    if short.startswith("tiktok"):
        return {"load_data": _list([] if empty else _TIKTOK)}
    raise KeyError(f"no synthetic fetch stub for {service}")


def load_call(service):
    """Call the service's BigQuery load function directly with its default destination."""
    frame = {"order_id": ["1", "2"], "name": ["synthetic", None]}
    if "meta-ads" in service:  # load_to_bigquery has no defaults; run_export passes these module values
        return {"action": "call", "function": "load_to_bigquery", "dataframe": frame,
                "args": [None, "@DATASET_ID", "@TABLE_ID"]}
    return {"action": "call", "function": "insert_to_bigquery", "dataframe": frame}


# Inside the container there is no repository credentials/ folder; model that so no service
# ever reaches for a key file during the tests.
CONTAINER_PATHS = {"cloud-run-pancake-order": {"SERVICE_ACCOUNT_FILE": "/nonexistent/google-credentials.json"}}


def scenario(service, name, **fields):
    base = {"name": name, "set_paths": CONTAINER_PATHS.get(service, {})}
    base.update(fields)
    return base


def all_services():
    return sorted(p.name for p in CLOUD_RUN.iterdir() if p.is_dir())


def run_all(build_scenarios, env_for=None, workers=6):
    """Run build_scenarios(service) for every service in parallel: {service: {name: result}}."""
    from concurrent.futures import ThreadPoolExecutor

    def one(service):
        results = run_service(service, build_scenarios(service), env=(env_for or (lambda s: None))(service))
        return service, {r["name"]: r for r in results}

    with ThreadPoolExecutor(max_workers=workers) as pool:
        return dict(pool.map(one, all_services()))


@lru_cache(maxsize=1)
def service_python_problem():
    """None when SERVICE_PYTHON can run the services, else a reason to skip."""
    code = "import importlib, sys\n" + "".join(
        f"importlib.import_module({name!r})\n" for name in REQUIRED_MODULES
    ) + "assert sys.version_info >= (3, 11), sys.version\n"
    try:
        result = subprocess.run([SERVICE_PYTHON, "-c", code], capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"service interpreter {SERVICE_PYTHON} unusable: {exc}"
    if result.returncode != 0:
        last = (result.stderr.strip().splitlines() or ["unknown error"])[-1]
        return f"service dependencies missing in {SERVICE_PYTHON}: {last}"
    return None


def run_service(service, scenarios, env=None, adc_project="marine-cycle-484213-b4", timeout=600):
    """Run scenarios (list of dicts) in one isolated child; return one result dict per scenario."""
    folder = CLOUD_RUN / service
    if not folder.is_dir():
        raise FileNotFoundError(folder)
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        request_file, result_file = tmp_path / "request.json", tmp_path / "result.json"
        request_file.write_text(json.dumps({"scenarios": scenarios, "adc_project": adc_project,
                                            "credential_names": sorted(CREDENTIAL_VALUES)}), encoding="utf-8")
        child_env = {key: os.environ[key] for key in ("PATH", "LANG", "SYSTEMROOT") if key in os.environ}
        child_env.update({"HOME": tmp, "CLOUDSDK_CONFIG": tmp, "PYTHONDONTWRITEBYTECODE": "1", "TZ": "UTC"})
        child_env.update(CREDENTIAL_VALUES)
        child_env.update(env or {})
        completed = subprocess.run(
            [SERVICE_PYTHON, "-B", str(CHILD), str(request_file), str(result_file)],
            cwd=folder, env=child_env, capture_output=True, text=True, timeout=timeout,
        )
        if completed.returncode != 0 or not result_file.exists():
            raise RuntimeError(
                f"{service}: harness child failed ({completed.returncode}): {completed.stderr[-2000:]}"
            )
        return json.loads(result_file.read_text(encoding="utf-8"))
