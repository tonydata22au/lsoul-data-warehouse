"""Offline checks for export paths and pagination; no cloud credentials needed."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    'warehouse_export', Path(__file__).resolve().parents[1] / 'scripts/export_warehouse_definitions.py')
export = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(export)


class ExportTests(unittest.TestCase):
    def test_reject_path_escape(self):
        for path in ('/tmp/outside', '../outside', 'definitions/../../outside', ''):
            with self.subTest(path=path), self.assertRaises(ValueError):
                export.safe_path(path)

    def test_paginate_until_token_exhausted(self):
        instance = export.Exporter.__new__(export.Exporter)
        calls = []
        responses = iter([{'items': [1], 'nextPageToken': 'next'}, {'items': [2]}])
        def get(service, path, params):
            calls.append(dict(params))
            return next(responses)
        instance.get = get
        self.assertEqual(instance.pages('test', 'path', 'items', {'pageSize': 1}), [1, 2])
        self.assertEqual(calls, [{'pageSize': 1}, {'pageSize': 1, 'pageToken': 'next'}])

    def test_repository_and_workspace_api_shapes(self):
        for resource in ('projects/p/locations/l/repositories/r',
                         'projects/p/locations/l/repositories/r/workspaces/w'):
            with self.subTest(resource=resource), tempfile.TemporaryDirectory() as directory:
                instance = export.Exporter.__new__(export.Exporter)
                instance.output = Path(directory)
                instance.manifest = {'files': []}
                workspace = '/workspaces/' in resource
                def pages(service, path, key, params):
                    if not params['path']:
                        return [{'directory': 'definitions'}, {'directory': '.venv'},
                                {'directory': 'node_modules'}, {'directory': '.vscode'}]
                    return [{'file': 'definitions/a.sqlx' if workspace else 'a.sqlx'}]
                def get(service, path, params):
                    self.assertEqual(params['path'], 'definitions/a.sqlx')
                    return {'fileContents' if workspace else 'contents': 'U0VMRUNUIDE7'}
                instance.pages = pages
                instance.get = get
                self.assertEqual(instance.source_tree(resource, Path('source')), 1)
                self.assertEqual((Path(directory) / 'source/definitions/a.sqlx').read_text(), 'SELECT 1;')

    def test_duplicate_exports_do_not_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            instance = export.Exporter.__new__(export.Exporter)
            instance.output = Path(directory)
            instance.manifest = {'files': []}
            instance.write('tables/a.sql', 'CREATE TABLE a;', {'resource': 'a'})
            with self.assertRaises(ValueError):
                instance.write('tables/a.sql', 'changed', {'resource': 'b'})
            self.assertEqual((Path(directory) / 'tables/a.sql').read_text(), 'CREATE TABLE a;')
            self.assertEqual(len(instance.manifest['files']), 1)


if __name__ == '__main__':
    unittest.main()
