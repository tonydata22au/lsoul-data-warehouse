"""Tests for the offline pipeline manifest (scripts/build_pipeline_manifest.py).

Nothing here imports a pipeline module, calls an API or touches BigQuery.
"""
import json
import re
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import build_pipeline_manifest as bpm  # noqa: E402


def entry(manifest, path):
    matches = [p for p in manifest["pipelines"] if p["path"] == path]
    if len(matches) != 1:
        raise AssertionError(f"expected one entry for {path}, found {len(matches)}")
    return matches[0]


def resolved(pipeline):
    return {d["table"] for d in pipeline["destinations"] if d.get("table")}


def cr_path(service):
    scripts = sorted((ROOT / "src" / "cloud_run" / service).glob("cr-*.py"))
    if len(scripts) != 1:
        raise AssertionError(f"{service}: expected one cr-*.py, found {len(scripts)}")
    return scripts[0].relative_to(ROOT).as_posix()


class RealRepositoryManifest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = bpm.build_manifest(ROOT)

    def test_schema_header(self):
        self.assertEqual(self.manifest["schema_version"], 1)
        self.assertEqual(self.manifest["generator"], "scripts/build_pipeline_manifest.py")

    def test_every_pipeline_file_has_an_entry(self):
        paths = {p["path"] for p in self.manifest["pipelines"]}
        for folder in ("local_run", "csv_export", "schema"):
            for path in sorted((ROOT / "src" / folder).glob("*.py")):
                with self.subTest(path=path.name):
                    self.assertIn(path.relative_to(ROOT).as_posix(), paths)
        for script in sorted((ROOT / "src" / "cloud_run").glob("*/cr-*.py")):
            with self.subTest(path=script.name):
                self.assertIn(script.relative_to(ROOT).as_posix(), paths)

    def test_app_runner_and_init_are_not_pipelines(self):
        names = {Path(p["path"]).name for p in self.manifest["pipelines"]}
        self.assertNotIn("app_runner.py", names)
        self.assertNotIn("__init__.py", names)

    def test_every_cloud_run_script_resolves_a_destination(self):
        for p in self.manifest["pipelines"]:
            if p["variant"] == "cloud_run" and Path(p["path"]).name.startswith("cr-"):
                with self.subTest(path=p["path"]):
                    self.assertTrue(resolved(p), p["destinations"])

    def test_both_pancake_order_services_write_raw_order(self):
        for service in ("cloud-run-pancake-order", "cloud-run-pancake-order_returned"):
            p = entry(self.manifest, cr_path(service))
            with self.subTest(service=service):
                self.assertIn("raw.raw_order", resolved(p))
                self.assertEqual(p["source_system"], "pancake")
                self.assertEqual(p["service"], service)

    def test_magento_env_default_destination_resolves(self):
        p = entry(self.manifest, cr_path("cloud-run-magento-order"))
        self.assertIn("raw.raw_magento_order", resolved(p))
        self.assertEqual(p["source_system"], "magento")

    def test_schema_script_destination(self):
        p = entry(self.manifest, "src/schema/bq-raw_dianplus..order.py")
        self.assertEqual(p["variant"], "schema")
        self.assertIn("raw.raw_dianplus_order", resolved(p))

    def test_source_system_falls_back_to_docs_then_destination(self):
        by_docs = entry(self.manifest, "src/csv_export/CSV_V1_data_export_variations.py")
        self.assertEqual(by_docs["source_system"], "pancake")
        self.assertEqual(by_docs["destinations"], [])
        by_table = entry(self.manifest, "src/schema/bq-raw_variations.py")
        self.assertEqual(by_table["source_system"], "pancake")

    def test_env_vars_are_names_only(self):
        name = re.compile(r"^[A-Z][A-Z0-9_]*$")
        example = set(re.findall(r"(?m)^([A-Z][A-Z0-9_]*)=", (ROOT / ".env.example").read_text()))
        for p in self.manifest["pipelines"]:
            for var in p["env_vars"]:
                with self.subTest(path=p["path"], var=var):
                    self.assertRegex(var, name)
        magento = entry(self.manifest, cr_path("cloud-run-magento-order"))
        self.assertIn("MAGENTO_PASSWORD", magento["env_vars"])
        self.assertIn("MAGENTO_PASSWORD", example)

    def test_manifest_has_no_secret_like_values(self):
        text = bpm.render(self.manifest)
        self.assertNotRegex(text, r"(?i)\"(password|secret|token|api_key)\"\s*:")
        self.assertNotIn("BEGIN PRIVATE KEY", text)

    def test_symbols_have_line_ranges(self):
        p = entry(self.manifest, cr_path("cloud-run-pancake-order"))
        functions = {s["name"]: s for s in p["symbols"] if s["kind"] == "function"}
        self.assertIn("insert_to_bigquery", functions)
        symbol = functions["insert_to_bigquery"]
        self.assertLessEqual(symbol["start_line"], symbol["end_line"])

    def test_render_is_deterministic(self):
        self.assertEqual(bpm.render(self.manifest), bpm.render(bpm.build_manifest(ROOT)))


class SourceSystemFromRawDataset(unittest.TestCase):
    """All raw tables share the dataset `raw`; only Pancake's table names carry no source prefix."""

    def test_unprefixed_raw_table_is_pancake(self):
        self.assertEqual(bpm.source_system("src/schema/x.py", "", "raw.raw_variations"), "pancake")

    def test_prefixed_raw_table_keeps_its_source(self):
        self.assertEqual(bpm.source_system("src/schema/x.py", "", "raw.raw_tiktok_ads"), "tiktok")
        self.assertEqual(bpm.source_system("src/schema/x.py", "", "raw.raw_dianplus_order"), "dianplus")

    def test_meta_ads_reporting_table_is_not_guessed_as_pancake(self):
        self.assertIsNone(bpm.source_system("src/schema/x.py", "", "raw.raw_ads_reporting_a"))


class SyntheticRepository(unittest.TestCase):
    """A tiny repository exercises the extraction rules and --check mode."""

    def make_repo(self, root):
        service = root / "src" / "cloud_run" / "cloud-run-pancake-order"
        service.mkdir(parents=True)
        (service / "app_runner.py").write_text("app = None\n")
        (service / "cr-pancake-order.py").write_text(textwrap.dedent('''\
            """Pancake orders."""
            import os
            from google.cloud import bigquery

            API_KEY = os.environ["PANCAKE_API_KEY"]
            DATASET_ID = "raw_pancake"
            TABLE_ID = "raw_order"


            def load_data():
                """Fetch every page."""
                return []


            def insert_to_bigquery(df):
                config = bigquery.LoadJobConfig(
                    write_disposition=bigquery.WriteDisposition.WRITE_APPEND)
                return config
            '''))
        (root / "src" / "local_run").mkdir(parents=True)
        (root / "src" / "local_run" / "magento_order.py").write_text(textwrap.dedent('''\
            import os
            BQ_DATASET = os.getenv("BQ_DATASET", "magento")
            BQ_TABLE = os.getenv("BQ_TABLE", "raw_magento_order")
            PORT = os.environ.get("PORT", "8080")
            '''))
        (root / "docs").mkdir()
        (root / "docs" / "pipelines.md").write_text(textwrap.dedent('''\
            | Service folder | Source endpoint | Destination | Load |
            |---|---|---|---|
            | cloud-run-pancake-order | Pancake `/orders` | `raw_pancake.raw_order` | WA |

            | File | Source | Destination |
            |---|---|---|
            | magento_order.py | Magento | `${BQ_PROJECT:-p}.${BQ_DATASET:-magento}.${BQ_TABLE:-raw_magento_order}` |
            '''))

    def test_extraction_rules(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            manifest = bpm.build_manifest(root)
            self.assertEqual(len(manifest["pipelines"]), 2)
            cr = entry(manifest, "src/cloud_run/cloud-run-pancake-order/cr-pancake-order.py")
            self.assertEqual(cr["variant"], "cloud_run")
            self.assertEqual(cr["service"], "cloud-run-pancake-order")
            self.assertEqual(cr["write_dispositions"], ["WRITE_APPEND"])
            self.assertEqual(cr["env_vars"], ["PANCAKE_API_KEY"])
            evidence = {(d["table"], d["evidence"]) for d in cr["destinations"]}
            self.assertIn(("raw_pancake.raw_order", "docs/pipelines.md"), evidence)
            self.assertIn(("raw_pancake.raw_order", "code"), evidence)
            symbols = {s["name"]: s for s in cr["symbols"]}
            self.assertEqual(symbols["load_data"]["doc"], "Fetch every page.")
            self.assertEqual(symbols["load_data"]["start_line"], 10)
            self.assertEqual(symbols["load_data"]["end_line"], 12)

            local = entry(manifest, "src/local_run/magento_order.py")
            self.assertEqual(local["variant"], "local_run")
            self.assertIsNone(local["service"])
            self.assertEqual(local["source_system"], "magento")
            self.assertEqual(resolved(local), {"magento.raw_magento_order"})
            self.assertEqual(local["env_vars"], ["BQ_DATASET", "BQ_TABLE", "PORT"])
            self.assertNotIn("8080", bpm.render(manifest))

    def test_check_mode_detects_stale_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            self.assertEqual(bpm.main(["--root", str(root)]), 0)
            self.assertEqual(bpm.main(["--root", str(root), "--check"]), 0)
            script = root / "src/cloud_run/cloud-run-pancake-order/cr-pancake-order.py"
            script.write_text(script.read_text().replace('"raw_order"', '"raw_order_v2"'))
            self.assertEqual(bpm.main(["--root", str(root), "--check"]), 1)

    def test_check_mode_fails_when_manifest_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            self.assertEqual(bpm.main(["--root", str(root), "--check"]), 1)

    def test_written_file_is_valid_json_with_trailing_newline(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            bpm.main(["--root", str(root)])
            text = (root / "metadata" / "pipeline_manifest.json").read_text()
            self.assertTrue(text.endswith("\n"))
            self.assertEqual(json.loads(text)["schema_version"], 1)


if __name__ == "__main__":
    unittest.main()
