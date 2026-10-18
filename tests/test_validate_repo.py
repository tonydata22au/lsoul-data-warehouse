"""Run the offline repository checks as unit tests (no network, no BigQuery)."""
import json
import os
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import validate_repo  # noqa: E402


class RepositoryChecks(unittest.TestCase):
    def test_static_checks_pass(self):
        for check in validate_repo.STATIC_CHECKS:
            with self.subTest(check=check.__name__):
                errors, _ = check()
                self.assertEqual(errors, [])


class CredentialScanner(unittest.TestCase):
    def scan(self, source, filename="pipeline.py"):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "src").mkdir()
            (root / "src" / filename).write_text(textwrap.dedent(source))
            saved = validate_repo.ROOT, validate_repo.SRC
            validate_repo.ROOT, validate_repo.SRC = root, root / "src"
            try:
                errors, _ = validate_repo.check_no_hardcoded_credentials()
            finally:
                validate_repo.ROOT, validate_repo.SRC = saved
            return errors

    def test_flags_hardcoded_literals(self):
        errors = self.scan('''
            import os
            API_KEY = "abcd1234efgh5678"
            token = os.getenv("SOME_TOKEN", "abcd1234efgh5678")
            headers = {"Access-Token": "abcd1234efgh5678"}
        ''')
        self.assertEqual(len(errors), 3, errors)

    def test_flags_other_literal_shapes(self):
        errors = self.scan('''
            import os
            PASSWORD = "opsdataonly"
            ACCESS_TOKEN = "EAAB/abc123+def456=="
            api_key = os.getenv("API_KEY", default="abcd1234efgh5678")
        ''', filename="extensionless_script")
        self.assertEqual(len(errors), 3, errors)

    def test_scans_notebook_code_cells(self):
        notebook = {"cells": [{"cell_type": "code", "source": ["%load_ext x\n"]},
                              {"cell_type": "code", "source": ["token = 'abcd1234efgh5678'\n"]}]}
        errors = self.scan(json.dumps(notebook), filename="analysis.ipynb")
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("analysis.ipynb#cell1", errors[0])

    def test_ignores_paths_and_urls(self):
        errors = self.scan('''
            TOKEN_FILE_KEY = "/Users/someone/credentials/key-2026.json"
            api_key_docs = "https://example.com/docs/v2/api-key"
        ''')
        self.assertEqual(errors, [])

    def test_allows_environment_lookups(self):
        errors = self.scan('''
            import os
            API_KEY = os.environ["PANCAKE_API_KEY"]
            headers = {"Access-Token": os.environ["TIKTOK_ACCESS_TOKEN"]}
            META = os.getenv("META_ACCESS_TOKEN", "")
        ''')
        self.assertEqual(errors, [])


class ServiceImportIsolation(unittest.TestCase):
    """check_service_imports must not expose real credentials, .env values or the network."""

    def run_fake_service(self, app_runner_source):
        with tempfile.TemporaryDirectory() as tmp:
            service = Path(tmp) / "cloud-run-fake"
            (service / "dotenv").mkdir(parents=True)
            # Stand-in for python-dotenv that would leak a value if it were called.
            (service / "dotenv" / "__init__.py").write_text(
                "from .main import load_dotenv\n")
            (service / "dotenv" / "main.py").write_text(
                "import os\ndef load_dotenv(*a, **k):\n    os.environ['LEAKED_FROM_DOTENV'] = '1'\n    return True\n")
            (service / "app_runner.py").write_text(textwrap.dedent(app_runner_source))
            saved = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
            os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = "/real/key.json"
            try:
                return validate_repo.check_service_imports([service])
            finally:
                if saved is None:
                    del os.environ["GOOGLE_APPLICATION_CREDENTIALS"]
                else:
                    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = saved

    def test_environment_is_isolated(self):
        errors, warnings = self.run_fake_service('''
            import os
            from dotenv import load_dotenv
            load_dotenv()
            assert "LEAKED_FROM_DOTENV" not in os.environ, "dotenv was not disabled"
            assert "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ, "Google credentials leaked"
            assert os.environ["PANCAKE_API_KEY"] == "dummy"
            assert os.path.expanduser("~") == os.environ["CLOUDSDK_CONFIG"]
            app = object()
        ''')
        self.assertEqual((errors, warnings), ([], []))

    def test_network_is_blocked(self):
        errors, _ = self.run_fake_service('''
            import socket
            socket.create_connection(("example.com", 443), timeout=1)
            app = object()
        ''')
        self.assertEqual(len(errors), 1)
        self.assertIn("network access attempted during import", errors[0])


if __name__ == "__main__":
    unittest.main()
