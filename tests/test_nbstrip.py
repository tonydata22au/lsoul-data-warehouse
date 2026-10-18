"""Tests for the notebook output clean filter (scripts/nbstrip.py)."""
import json
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "nbstrip.py"


def run_filter(data):
    return subprocess.run([sys.executable, str(SCRIPT)], input=data, capture_output=True, check=True).stdout


class NotebookStrip(unittest.TestCase):
    def test_removes_outputs_and_execution_counts(self):
        notebook = {
            "cells": [
                {"cell_type": "code", "source": ["1 + 1"], "metadata": {"executionInfo": {"t": 1}},
                 "execution_count": 3, "outputs": [{"output_type": "execute_result", "data": {"text/plain": ["2"]}}]},
                {"cell_type": "markdown", "source": ["# Title"], "metadata": {}},
            ],
            "metadata": {"widgets": {"state": {}}},
            "nbformat": 4,
            "nbformat_minor": 5,
        }
        stripped = json.loads(run_filter(json.dumps(notebook).encode()))
        code, markdown = stripped["cells"]
        self.assertEqual(code["outputs"], [])
        self.assertIsNone(code["execution_count"])
        self.assertNotIn("executionInfo", code["metadata"])
        self.assertEqual(code["source"], ["1 + 1"])
        self.assertEqual(markdown["source"], ["# Title"])
        self.assertNotIn("widgets", stripped["metadata"])

    def test_passes_through_non_notebook_input(self):
        self.assertEqual(run_filter(b"not json"), b"not json")


if __name__ == "__main__":
    unittest.main()
