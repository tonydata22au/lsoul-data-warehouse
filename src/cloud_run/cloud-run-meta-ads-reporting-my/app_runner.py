import importlib.util
from pathlib import Path

module_path = Path(__file__).with_name("cr-meta-ads_reporting-my.py")
spec = importlib.util.spec_from_file_location("cr_meta_ads_reporting_my", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

app = module.app
