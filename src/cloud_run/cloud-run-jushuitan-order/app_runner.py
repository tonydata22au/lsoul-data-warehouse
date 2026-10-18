import importlib.util
from pathlib import Path

module_path = Path(__file__).with_name("cr-jushuitan-order.py")
spec = importlib.util.spec_from_file_location("cr_jushuitan_order", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

app = module.app
