"""Cloud Function entrypoint wrapper for surfosm inventory export."""

import importlib.util
from pathlib import Path

module_path = Path(__file__).with_name("cr-surfosm-inventory.py")
spec = importlib.util.spec_from_file_location("cr_surfosm_inventory", module_path)
module = importlib.util.module_from_spec(spec)
if spec is None or spec.loader is None:
    raise ImportError("Failed to load cr-surfosm-inventory.py")
spec.loader.exec_module(module)


def export_inventory(request):
    """Google Cloud Function HTTP entrypoint."""
    return module.export_inventory(request)
