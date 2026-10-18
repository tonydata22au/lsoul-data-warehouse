import importlib.util
from pathlib import Path

module_path = Path(__file__).with_name("cr-pancake-warehouse_transfer.py")
spec = importlib.util.spec_from_file_location("cr_pancake_warehouse_transfer", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

app = module.app
