import importlib.util
from pathlib import Path

module_path = Path(__file__).with_name("cr-pancake-stats_inventory_product.py")
spec = importlib.util.spec_from_file_location("cr_pancake_stats_inventory_product", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

app = module.app
