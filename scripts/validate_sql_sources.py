#!/usr/bin/env python3
"""Validate reviewed source divergence without relabelling proposed SQL as deployed."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'sql/source_provenance.json'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_manifest(root, manifest):
    errors = []
    if manifest.get('version') != 1:
        errors.append('Unsupported SQL provenance version')
    paths, objects = set(), set()

    def path_for(value, prefix):
        if not isinstance(value, str):
            raise ValueError('Missing path')
        path = (root / value).resolve()
        if not path.is_relative_to((root / prefix).resolve()):
            raise ValueError('Path outside ' + prefix + ': ' + value)
        if not path.is_file():
            raise ValueError('Missing file: ' + value)
        return path

    def digest(path, expected):
        if not isinstance(expected, str) or not re.fullmatch(r'[0-9a-f]{64}', expected):
            raise ValueError('Invalid hash for ' + str(path))
        if sha256(path) != expected:
            raise ValueError('Hash mismatch: ' + str(path.relative_to(root)))

    for entry in manifest.get('sources', []):
        try:
            source = path_for(entry['path'], 'sql')
            if source.is_relative_to((root / 'sql/live').resolve()):
                raise ValueError('Maintained source cannot be inside sql/live')
            if entry['path'] in paths or entry['object'] in objects:
                raise ValueError('Duplicate source path/object')
            paths.add(entry['path'])
            objects.add(entry['object'])
            if entry['status'] not in ('pending', 'preexisting-unverified') or not entry['reason'].strip():
                raise ValueError('Missing reason or invalid source status')
            digest(source, entry['source_sha256'])
            digest(path_for(entry['snapshot_path'], 'sql/live'), entry['snapshot_sha256'])
            preserved = entry.get('preserved_local_source')
            if preserved:
                digest(path_for(preserved['path'], 'sql/archive'), preserved['sha256'])
                if not preserved['reason'].strip():
                    raise ValueError('Missing preserved-source reason')
            if not re.fullmatch(r'[0-9a-f]{64}', entry['baseline_ddl_sha256']):
                raise ValueError('Missing captured baseline DDL hash')
            if not entry.get('baseline_captured_at'):
                raise ValueError('Missing baseline capture provenance')
            header = re.search(
                r'CREATE\s+(?:OR\s+REPLACE\s+)?(?:TABLE\s+)?(?:FUNCTION|PROCEDURE)\s+([^\s(]+)',
                source.read_text(), re.I)
            if not header or header[1].replace('`', '') != entry['object']:
                raise ValueError('Source object does not match manifest')
        except (KeyError, ValueError, OSError) as exc:
            errors.append(str(exc))

    amendments = set()
    for entry in manifest.get('snapshot_amendments', []):
        try:
            path = path_for(entry['path'], 'sql/live')
            if entry['path'] in amendments:
                raise ValueError('Duplicate snapshot amendment')
            amendments.add(entry['path'])
            digest(path, entry['current_sha256'])
            if not re.fullmatch(r'[0-9a-f]{64}', entry['original_sha256']):
                raise ValueError('Missing original snapshot hash')
            if not re.fullmatch(r'[0-9a-f]{40}', entry['commit']) or not entry['reason'].strip():
                raise ValueError('Missing amendment commit/reason')
        except (KeyError, ValueError, OSError) as exc:
            errors.append(str(exc))
    return errors


def main():
    manifest = json.loads((ROOT / MANIFEST).read_text())
    errors = validate_manifest(ROOT, manifest)
    for error in errors:
        print('FAIL', error)
    if not errors:
        print('PASS SQL source provenance (pending sources are not deployment evidence)')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
