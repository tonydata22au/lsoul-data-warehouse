import importlib.util
from pathlib import Path

module_path = Path(__file__).with_name("cr-pancake-inventory_histories.py")
spec = importlib.util.spec_from_file_location("cr_pancake_inventory_histories", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

app = module.app
