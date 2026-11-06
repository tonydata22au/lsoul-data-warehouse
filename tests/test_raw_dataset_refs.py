"""Guard: raw tables live in the single BigQuery dataset `raw` (offline; reads files only).

Plan: tasks/raw-dataset-plan.md. Two checks:

1. No editable Python under src/ or SQL under sql/ still points at an old raw dataset
   (`raw_pancake`, `raw_tiktok`, `raw_meta`, or `<source>.raw_*` in the mixed source datasets).
   Excluded: sql/live/ (generated snapshot), sql/archive/, and the cutover script
   sql/migrations/raw_dataset_consolidation.sql, which must name the old datasets.
2. That cutover script names exactly the 31 old raw tables, each with its `raw.<table>` copy.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = "sql/migrations/raw_dataset_consolidation.sql"
EXCLUDED_DIRS = ("sql/live/", "sql/archive/")

# Qualified references. The lookbehind skips file names such as `bq-raw_pancake..raw_order.py`
# and `zarchived-raw_pancake.sp_...sql`, which are paths, not dataset references.
OLD = re.compile(
    r"(?<![\w-])(raw_pancake|raw_tiktok|raw_meta)\."
    r"|(?<![\w-])(dianplus|jushuitan|magento|surfosm)\.raw_"
)
# Bare dataset literals in Python: DATASET_ID = 'dianplus', os.getenv("BQ_DATASET", "surfosm"), ...
OLD_PY = re.compile(r"[\"'](raw_pancake|raw_tiktok|raw_meta|dianplus|jushuitan|magento|surfosm)[\"']")

# Live raw base tables on 2026-11-05 (tasks/raw-dataset-plan.md, "Live inventory").
INVENTORY = {
    "raw_pancake": {
        "raw_customer", "raw_inventory_histories", "raw_order", "raw_orders_returned",
        "raw_product_variations", "raw_stats_inventory_variations", "raw_stats_product",
    },
    "raw_tiktok": {
        "raw_tiktok_ad_group", "raw_tiktok_ads", "raw_tiktok_campaign", "raw_tiktok_gmv_max_report",
        "raw_tiktok_reporting_basic_auction_ad", "raw_tiktok_reporting_basic_auction_campaign",
        "raw_tiktok_thai_ad_group", "raw_tiktok_thai_ads", "raw_tiktok_thai_campaign",
        "raw_tiktok_thai_gmv_max_report", "raw_tiktok_thai_reporting_basic_auction_ad",
    },
    "raw_meta": {"raw_ads_reporting_a", "raw_ads_reporting_ecom", "raw_ads_reporting_my"},
    "dianplus": {
        "raw_dianplus_inventory", "raw_dianplus_order", "raw_dianplus_order_refund", "raw_dianplus_product",
    },
    "jushuitan": {"raw_jushuitan_inventory", "raw_jushuitan_taobao_tmall_order_manual"},
    "magento": {"raw_magento_order"},
    "surfosm": {"raw_surfosm_inventory", "raw_surfosm_order", "raw_surfosm_order_return"},
}
OLD_TABLE_REF = re.compile(
    r"(?<![\w-])(raw_pancake|raw_tiktok|raw_meta|dianplus|jushuitan|magento|surfosm)\.(raw_\w+)"
)


def offending_lines(relpath, text):
    """(line number, line) pairs in `text` that point at an old raw dataset; [] if exempt."""
    if relpath == MIGRATION or relpath.startswith(EXCLUDED_DIRS):
        return []
    patterns = [OLD, OLD_PY] if relpath.startswith("src/") and relpath.endswith(".py") else [OLD]
    return [
        (number, line.strip())
        for number, line in enumerate(text.splitlines(), 1)
        if any(p.search(line) for p in patterns)
    ]


def migration_references(text):
    """Map each old dataset to the raw tables `text` reads or writes there."""
    found = {}
    for dataset, table in OLD_TABLE_REF.findall(text):
        found.setdefault(dataset, set()).add(table)
    return found


def scanned_files():
    for path in sorted((ROOT / "src").rglob("*.py")):
        yield path
    for path in sorted((ROOT / "sql").rglob("*")):
        if path.is_file() and path.suffix in (".sql", ".json", ".md"):
            yield path


class GuardSelfTest(unittest.TestCase):
    def test_bare_dataset_literal_in_src_python_is_flagged(self):
        hits = offending_lines("src/schema/bq-raw_dianplus..order.py", "DATASET_ID = 'dianplus'\n")
        self.assertEqual(hits, [(1, "DATASET_ID = 'dianplus'")])

    def test_getenv_default_to_old_dataset_is_flagged(self):
        text = 'BQ_DATASET = os.getenv("BQ_DATASET", "surfosm")\n'
        self.assertEqual(len(offending_lines("src/cloud_run/x/cr-x.py", text)), 1)

    def test_old_reference_in_staging_or_function_sql_is_flagged(self):
        line = "SELECT * FROM `marine-cycle-484213-b4.raw_pancake.raw_order`"
        self.assertEqual(len(offending_lines("sql/staging/stg_pancake.stg_order.sql", line)), 1)
        self.assertEqual(len(offending_lines("sql/functions/reportdb.fn_x.sql", line)), 1)
        mixed = "FROM `marine-cycle-484213-b4.dianplus.raw_dianplus_order`"
        self.assertEqual(len(offending_lines("sql/staging/dianplus.stg_dianplus_order.sql", mixed)), 1)

    def test_old_reference_in_migration_live_and_archive_is_exempt(self):
        line = "CREATE TABLE raw.raw_order COPY `marine-cycle-484213-b4.raw_pancake.raw_order`;"
        self.assertEqual(offending_lines(MIGRATION, line), [])
        self.assertEqual(offending_lines("sql/live/bigquery/x.sql", line), [])
        self.assertEqual(offending_lines("sql/archive/zarchived-x.sql", line), [])

    def test_other_migration_files_are_not_exempt(self):
        line = "SELECT 1 FROM `marine-cycle-484213-b4.raw_pancake.raw_order`"
        self.assertEqual(len(offending_lines("sql/migrations/other.sql", line)), 1)

    def test_new_dataset_and_file_names_are_not_flagged(self):
        text = (
            'RAW = os.getenv("BQ_RAW_DATASET", "raw")\n'
            "FROM `marine-cycle-484213-b4.raw.raw_dianplus_order`\n"
            "python3 src/schema/bq-raw_pancake..raw_order.py\n"
            "[old](../archive/zarchived-raw_pancake.sp_check_partition_insert_dates.sql)\n"
            "FROM `marine-cycle-484213-b4.dianplus.core_dianplus_order`\n"
        )
        self.assertEqual(offending_lines("src/cloud_run/x/cr-x.py", text), [])
        self.assertEqual(offending_lines("sql/checks/README.md", text), [])

    def test_migration_reference_parser(self):
        text = "COPY `p.raw_pancake.raw_order`; COPY dianplus.raw_dianplus_order; raw.raw_order"
        self.assertEqual(
            migration_references(text),
            {"raw_pancake": {"raw_order"}, "dianplus": {"raw_dianplus_order"}},
        )


class RepositoryUsesRawDataset(unittest.TestCase):
    def test_no_editable_file_points_at_an_old_raw_dataset(self):
        problems = []
        for path in scanned_files():
            relpath = path.relative_to(ROOT).as_posix()
            for number, line in offending_lines(relpath, path.read_text(encoding="utf-8")):
                problems.append(f"{relpath}:{number}: {line[:160]}")
        self.assertEqual(problems, [], "old raw dataset references:\n" + "\n".join(problems))

    def test_every_cloud_run_service_reads_its_dataset_from_the_environment(self):
        # Rollback lever: each service writes to `raw` unless BQ_RAW_DATASET (or the older
        # BQ_DATASET of magento-order and surfosm-inventory) names another dataset.
        env_default = re.compile(r'os\.getenv\("(BQ_RAW_DATASET|BQ_DATASET)", "raw"\)')
        dataset_setting = re.compile(r"^\s*(def .*\bdataset_id=|DATASET_ID\s*=|BQ_DATASET\s*=)")
        services = sorted((ROOT / "src" / "cloud_run").glob("*/cr-*.py"))
        self.assertEqual(len(services), 30)
        for path in services:
            with self.subTest(service=path.parent.name):
                lines = [l for l in path.read_text(encoding="utf-8").splitlines() if dataset_setting.match(l)]
                self.assertTrue(any(env_default.search(line) for line in lines), lines)

    def test_migration_names_exactly_the_inventory(self):
        path = ROOT / MIGRATION
        self.assertTrue(path.is_file(), f"{MIGRATION} is missing")
        text = path.read_text(encoding="utf-8")
        self.assertEqual(migration_references(text), INVENTORY)
        for tables in INVENTORY.values():
            for table in tables:
                self.assertRegex(text, rf"(?<![\w-])raw\.{table}\b", f"no raw.{table} in {MIGRATION}")


if __name__ == "__main__":
    unittest.main()
