"""Verify the checked-in metadata/source snapshot without contacting Google Cloud."""
import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / 'sql/live'


class SnapshotTests(unittest.TestCase):
    def test_manifest_files_and_hashes(self):
        manifest = json.loads((SNAPSHOT / 'manifest.json').read_text())
        paths = set()
        for entry in manifest['files']:
            with self.subTest(path=entry['path']):
                path = (SNAPSHOT / entry['path']).resolve()
                self.assertTrue(path.is_relative_to(SNAPSHOT.resolve()))
                self.assertFalse(entry['path'] in paths, 'Duplicate manifest path: ' + entry['path'])
                paths.add(entry['path'])
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), entry['sha256'])
        actual = {str(p.relative_to(SNAPSHOT)) for p in SNAPSHOT.rglob('*') if p.is_file()}
        self.assertEqual(actual - paths, {'README.md', 'manifest.json', 'routine_sync.json'})

    def test_refreshed_routines_match_snapshot(self):
        sync = json.loads((SNAPSHOT / 'routine_sync.json').read_text())
        for entry in sync['updated']:
            with self.subTest(path=entry['path']):
                objects = entry.get('objects') or [entry['object']]
                parts = []
                for obj in objects:
                    project, dataset, name = obj.split('.')
                    self.assertEqual(project, 'marine-cycle-484213-b4')
                    sql = (SNAPSHOT / 'bigquery' / dataset / 'routines' / (name + '.sql')).read_text()
                    parts.append(re.sub(r'^CREATE\s+(?!OR\s+REPLACE)', 'CREATE OR REPLACE ',
                                        sql, count=1, flags=re.I))
                self.assertEqual((ROOT / entry['path']).read_text(), '\n'.join(parts))


if __name__ == '__main__':
    unittest.main()
