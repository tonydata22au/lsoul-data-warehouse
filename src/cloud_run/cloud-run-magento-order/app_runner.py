import importlib.util
from pathlib import Path

module_path = Path(__file__).with_name("cr-magento-order.py")
spec = importlib.util.spec_from_file_location("cr_magento_order", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

app = module.app
