import importlib.util
from pathlib import Path

module_path = Path(__file__).with_name("cr-pancake-variations.py")
spec = importlib.util.spec_from_file_location("cr_pancake_variations", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

app = module.app
