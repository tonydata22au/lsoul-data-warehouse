"""Verify the checked-in metadata/source snapshot without contacting Google Cloud."""
import hashlib
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / 'sql/live'
sys.path.insert(0, str(ROOT / 'scripts'))
from validate_sql_sources import validate_manifest


class SnapshotTests(unittest.TestCase):
    def provenance(self):
        manifest = json.loads((ROOT / 'sql/source_provenance.json').read_text())
        self.assertEqual(validate_manifest(ROOT, manifest), [])
        return manifest

    def test_manifest_files_and_hashes(self):
        manifest = json.loads((SNAPSHOT / 'manifest.json').read_text())
        amendments = {entry['path']: entry for entry in self.provenance()['snapshot_amendments']}
        paths = set()
        for entry in manifest['files']:
            with self.subTest(path=entry['path']):
                path = (SNAPSHOT / entry['path']).resolve()
                self.assertTrue(path.is_relative_to(SNAPSHOT.resolve()))
                self.assertFalse(entry['path'] in paths, 'Duplicate manifest path: ' + entry['path'])
                paths.add(entry['path'])
                amendment = amendments.get('sql/live/' + entry['path'])
                if amendment:
                    self.assertEqual(amendment['original_sha256'], entry['sha256'])
                expected = amendment['current_sha256'] if amendment else entry['sha256']
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected)
        self.assertTrue(set(amendments) <= {'sql/live/' + p for p in paths})
        # Finder metadata is ignored by Git and is not an exported SQL/configuration artifact.
        actual = {str(p.relative_to(SNAPSHOT)) for p in SNAPSHOT.rglob('*')
                  if p.is_file() and p.name != '.DS_Store'}
        self.assertEqual(actual - paths, {'README.md', 'manifest.json', 'routine_sync.json'})

    def test_refreshed_routines_match_snapshot(self):
        sync = json.loads((SNAPSHOT / 'routine_sync.json').read_text())
        maintained = {entry['path']: entry for entry in self.provenance()['sources']}
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
                if entry['path'] in maintained:
                    self.assertEqual(objects, [maintained[entry['path']]['object']])
                else:
                    self.assertEqual((ROOT / entry['path']).read_text(), '\n'.join(parts))


if __name__ == '__main__':
    unittest.main()
