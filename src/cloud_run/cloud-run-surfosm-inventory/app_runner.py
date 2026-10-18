import importlib.util
from pathlib import Path

from flask import Flask, request

module_path = Path(__file__).with_name("cr-surfosm-inventory.py")
spec = importlib.util.spec_from_file_location("cr_surfosm_inventory", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

app = Flask(__name__)


@app.route("/", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
@app.route("/run", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
@app.route("/healthz", methods=["GET"])
def handle_request():
	"""Cloud Run adapter that reuses the Cloud Function handler."""
	return module.export_inventory(request)
