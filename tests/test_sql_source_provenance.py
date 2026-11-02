"""Reject undeclared source changes and invalid provenance records."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from validate_sql_sources import validate_manifest


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ['sql/live', 'sql/functions']:
            (self.root / folder).mkdir(parents=True)
        self.old = b'CREATE FUNCTION `p.d.f`() AS (1);\n'
        self.new = b'CREATE OR REPLACE FUNCTION `p.d.f`() AS (2);\n'
        (self.root / 'sql/live/f.sql').write_bytes(self.old)
        (self.root / 'sql/functions/f.sql').write_bytes(self.new)
        sha = lambda value: hashlib.sha256(value).hexdigest()
        self.record = {
            'object': 'p.d.f', 'path': 'sql/functions/f.sql',
            'snapshot_path': 'sql/live/f.sql', 'snapshot_sha256': sha(self.old),
            'source_sha256': sha(self.new), 'baseline_ddl_sha256': sha(self.old),
            'status': 'pending', 'reason': 'Synthetic intentional source change',
            'baseline_captured_at': '2026-11-02',
        }
        self.manifest = {'version': 1, 'sources': [self.record], 'snapshot_amendments': []}

    def test_valid_pending_source(self):
        self.assertEqual(validate_manifest(self.root, self.manifest), [])

    def test_source_mutation_is_rejected(self):
        (self.root / self.record['path']).write_text('CREATE FUNCTION `p.d.f`() AS (3);')
        self.assertTrue(validate_manifest(self.root, self.manifest))

    def test_snapshot_mutation_is_rejected(self):
        (self.root / self.record['snapshot_path']).write_text('changed snapshot')
        self.assertTrue(validate_manifest(self.root, self.manifest))

    def test_different_object_is_rejected_even_with_correct_hash(self):
        changed = self.new.replace(b'p.d.f', b'p.d.other')
        (self.root / self.record['path']).write_bytes(changed)
        self.record['source_sha256'] = hashlib.sha256(changed).hexdigest()
        self.assertTrue(validate_manifest(self.root, self.manifest))

    def test_duplicate_and_path_escape_are_rejected(self):
        self.manifest['sources'].append(copy.deepcopy(self.record))
        self.assertTrue(validate_manifest(self.root, self.manifest))
        self.manifest['sources'].pop()
        self.record['path'] = '../outside.sql'
        self.assertTrue(validate_manifest(self.root, self.manifest))

    def test_missing_reason_or_invalid_state_is_rejected(self):
        self.record['reason'] = ''
        self.assertTrue(validate_manifest(self.root, self.manifest))
        self.record['reason'] = 'change'
        self.record['status'] = 'deployed-without-proof'
        self.assertTrue(validate_manifest(self.root, self.manifest))

    def test_amendment_requires_original_and_current_hashes(self):
        self.manifest['sources'] = []
        entry = {'path': 'sql/live/f.sql', 'original_sha256': '0' * 64,
                 'current_sha256': hashlib.sha256(self.old).hexdigest(),
                 'commit': 'a' * 40, 'reason': 'A documented post-capture edit'}
        self.manifest['snapshot_amendments'] = [entry]
        self.assertEqual(validate_manifest(self.root, self.manifest), [])
        entry['current_sha256'] = '1' * 64
        self.assertTrue(validate_manifest(self.root, self.manifest))

    def test_preserved_local_source_is_hash_checked(self):
        archive = self.root / 'sql/archive/zarchived-f.sql'
        archive.parent.mkdir()
        archive.write_bytes(self.old)
        self.record['preserved_local_source'] = {
            'path': str(archive.relative_to(self.root)),
            'sha256': hashlib.sha256(self.old).hexdigest(),
            'reason': 'Preserve local draft while preparing a live-based update',
        }
        self.assertEqual(validate_manifest(self.root, self.manifest), [])
        archive.write_bytes(b'overwritten local draft')
        self.assertTrue(validate_manifest(self.root, self.manifest))


if __name__ == '__main__':
    unittest.main()
