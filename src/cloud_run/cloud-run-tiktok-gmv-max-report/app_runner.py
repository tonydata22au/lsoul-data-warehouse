import importlib.util
from pathlib import Path

module_path = Path(__file__).with_name("cr-tiktok-gmv-max-report.py")
spec = importlib.util.spec_from_file_location("cr_tiktok_gmv_max_report", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

app = module.app
