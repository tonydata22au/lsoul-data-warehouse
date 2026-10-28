#!/usr/bin/env python3
"""Read-only cloud definition export; never executes exported SQL or reads table rows.

Requires authenticated gcloud/bq on PATH. Use a NEW output directory for each run.
Output is unreviewed source: inspect for secrets and personal literals before Git.
"""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


def safe_name(value):
    return urllib.parse.quote(value, safe='-_.')


def safe_path(value):
    path = Path(value)
    if path.is_absolute() or '..' in path.parts or not path.parts:
        raise ValueError('Unsafe source path')
    return path


def bq(project, args):
    result = subprocess.run(['bq', '--project_id=' + project, '--format=json', *args],
                            capture_output=True, text=True, timeout=300)
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr).strip())
    return json.loads(result.stdout or '[]')


class Exporter:
    def __init__(self, project, output):
        self.request_lock = threading.Lock()
        self.next_request = 0.0
        self.project = project
        self.output = output
        env = dict(os.environ)
        env['CLOUDSDK_METRICS_ENVIRONMENT'] = (
            env.get('CLOUDSDK_METRICS_ENVIRONMENT', '') + ' datacloud.codex').strip()
        self.token = subprocess.check_output(
            ['gcloud', 'auth', 'print-access-token'], env=env, text=True).strip()
        self.manifest = {'project': project, 'started_at': datetime.now(timezone.utc).isoformat(),
                         'datasets': [], 'repositories': [], 'transfers': [],
                         'coverage': [], 'gaps': [], 'files': []}

    def get(self, service, path, params=None):
        url = 'https://' + service + '.googleapis.com/v1/' + path
        if params:
            url += '?' + urllib.parse.urlencode(params)
        request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + self.token})
        for attempt in range(6):
            if service == 'dataform':
                # Default file-access quota is 120/minute/region; leave headroom.
                with self.request_lock:
                    delay = max(0.0, self.next_request - time.monotonic())
                    if delay:
                        time.sleep(delay)
                    self.next_request = time.monotonic() + 0.6
            try:
                with urllib.request.urlopen(request, timeout=90) as response:
                    return json.load(response)
            except urllib.error.HTTPError as exc:
                detail = json.load(exc).get('error', {})
                if exc.code in (429, 500, 502, 503, 504) and attempt < 5:
                    time.sleep(min(5 * 2 ** attempt, 45))
                    continue
                raise RuntimeError(str(exc.code) + ': ' + detail.get('message', 'API error')) from None

    def pages(self, service, path, key, params=None):
        params = dict(params or {})
        rows = []
        while True:
            response = self.get(service, path, params)
            rows.extend(response.get(key, []))
            if not response.get('nextPageToken'):
                return rows
            params['pageToken'] = response['nextPageToken']

    def write(self, relative, content, source):
        path = self.output / safe_path(str(relative))
        if path.exists():
            raise ValueError('Duplicate export path: ' + str(relative))
        path.parent.mkdir(parents=True, exist_ok=True)
        data = content.encode('utf-8') if isinstance(content, str) else content
        path.write_bytes(data)
        self.manifest['files'].append({'path': str(relative), 'source': source,
                                       'sha256': hashlib.sha256(data).hexdigest()})

    def gap(self, source, error):
        self.manifest['gaps'].append({'source': source, 'error': str(error)})
        print('GAP:', source, str(error)[:160], flush=True)

    def query(self, location, sql):
        return bq(self.project, ['--location=' + location, 'query', '--use_legacy_sql=false',
                               '--label=datacloud:codex', '--max_rows=1000000', sql])

    def dataset(self, dataset):
        ref = dataset['datasetReference']
        name, location = ref['datasetId'], dataset['location']
        record = {'dataset': name, 'location': location, 'type': dataset.get('type'), 'objects': {}}
        for view, prefix, namecol, kindcol in (
            ('TABLES', 'tables', 'table_name', 'table_type'),
            ('ROUTINES', 'routines', 'routine_name', 'routine_type')):
            source = f'{self.project}.{name}.INFORMATION_SCHEMA.{view}'
            try:
                rows = self.query(location, f'SELECT {namecol}, {kindcol}, ddl FROM `{source}` ORDER BY {namecol}')
                record['objects'][prefix] = len(rows)
                for row in rows:
                    object_name = row[namecol]
                    if not row.get('ddl'):
                        self.gap(source + ':' + object_name, 'DDL unavailable')
                        if prefix == 'tables':
                            try:
                                schema = bq(self.project, ['show', '--schema',
                                    f'{self.project}:{name}.{object_name}'])
                                relative = Path('bigquery') / safe_name(name) / 'schemas' / (safe_name(object_name) + '.json')
                                self.write(relative, json.dumps(schema, indent=2) + '\n',
                                           {'resource': f'{self.project}.{name}.{object_name}',
                                            'type': 'SCHEMA_ONLY', 'metadata_view': source})
                            except Exception as exc:
                                self.gap(source + ':' + object_name + ':schema', exc)
                        continue
                    sql = row['ddl'].replace('\r\n', '\n').rstrip()
                    if not sql.endswith(';'):
                        sql += ';'
                    relative = Path('bigquery') / safe_name(name) / prefix / (safe_name(object_name) + '.sql')
                    self.write(relative, sql + '\n', {'resource': f'{self.project}.{name}.{object_name}',
                                                       'type': row[kindcol], 'metadata_view': source})
            except Exception as exc:
                self.gap(source, exc)
        self.manifest['datasets'].append(record)
        print('DATASET', name, record['objects'], flush=True)

    def source_tree(self, resource, base):
        pending = ['']
        count = 0
        while pending:
            directory = pending.pop()
            entries = self.pages('dataform', resource + ':queryDirectoryContents', 'directoryEntries',
                                 {'path': directory, 'pageSize': 100})
            for entry in entries:
                if 'directory' in entry:
                    folder = entry['directory']
                    if '/workspaces/' not in resource:
                        folder = str(Path(directory) / folder)
                    if not set(Path(folder).parts) & {'.git', '.venv', 'venv', '.vscode', '__pycache__', 'node_modules', 'credentials'}:
                        pending.append(folder)
                    continue
                file = entry.get('file')
                if not file:
                    continue
                if '/workspaces/' not in resource:
                    file = str(Path(directory) / file)
                path = safe_path(file)
                # Only source/configuration formats; no credentials, data exports, or notebooks.
                if path.suffix.lower() not in {'.sql', '.sqlx', '.js', '.json', '.yaml', '.yml'}:
                    continue
                if re.search(r'(?i)(credential|secret|service.account|token|\.env)', str(path)):
                    self.gap(resource + '/' + file, 'Credential-like filename withheld')
                    continue
                content = self.get('dataform', resource + ':readFile', {'path': file})
                self.write(base / path, base64.b64decode(content.get('fileContents' if '/workspaces/' in resource else 'contents', ''), validate=True),
                           {'resource': resource, 'source_path': file})
                count += 1
        return count

    def repository(self, repo):
        resource = repo['name']
        location, identifier = resource.split('/')[3], resource.split('/')[-1]
        saved = repo.get('labels', {}).get('single-file-asset-type') == 'sql'
        category = 'saved_queries' if saved else 'dataform'
        title = repo.get('displayName') or identifier
        base = Path(category) / location / (safe_name(title) + '--' + identifier)
        record = {k: repo[k] for k in ('name', 'displayName', 'labels') if k in repo}
        record['path'] = str(base)
        record['workspaces'] = []
        try:
            record['head_files'] = self.source_tree(resource, base / 'head')
        except Exception as exc:
            if 'Reading from empty repo' in str(exc):
                record['head_state'] = 'empty'
            else:
                self.gap(resource + ':HEAD', exc)
        try:
            workspaces = self.pages('dataform', resource + '/workspaces', 'workspaces', {'pageSize': 100})
            for workspace in workspaces:
                name = workspace['name']
                try:
                    count = self.source_tree(name, base / 'workspaces' / safe_name(name.split('/')[-1]))
                    record['workspaces'].append({'name': name, 'files': count})
                except Exception as exc:
                    self.gap(name, exc)
            if not saved:
                for kind in ('releaseConfigs', 'workflowConfigs'):
                    configs = self.pages('dataform', resource + '/' + kind, kind, {'pageSize': 100})
                    # Keep operational config; exclude identity/auth fields.
                    allow = {'name', 'gitCommitish', 'cronSchedule', 'timeZone', 'releaseConfig',
                             'codeCompilationConfig', 'invocationConfig', 'disabled'}
                    cleaned = [{k: v for k, v in c.items() if k in allow} for c in configs]
                    for c in cleaned:
                        if isinstance(c.get('invocationConfig'), dict):
                            c['invocationConfig'].pop('serviceAccount', None)
                            c['invocationConfig'].pop('endUserAuthConfig', None)
                    if cleaned:
                        self.write(base / (kind + '.json'), json.dumps(cleaned, indent=2) + '\n',
                                   {'resource': resource + '/' + kind})
        except Exception as exc:
            self.gap(resource + ':configuration', exc)
        self.manifest['repositories'].append(record)
        print('REPOSITORY', title, record.get('head_files', record.get('head_state')), flush=True)

    def location(self, location):
        parent = f'projects/{self.project}/locations/{location}'
        coverage = {'location': location}
        repos = []
        try:
            repos = self.pages('dataform', parent + '/repositories', 'repositories', {'pageSize': 100})
            coverage['repositories'] = len(repos)
        except Exception as exc:
            self.gap(parent + '/repositories', exc)
        self.manifest['coverage'].append(coverage)
        return repos

    def transfers(self, location):
        parent = f'projects/{self.project}/locations/{location}'
        try:
            configs = self.pages('bigquerydatatransfer', parent + '/transferConfigs', 'transferConfigs',
                                 {'pageSize': 1000})
            for config in configs:
                record = {k: config[k] for k in ('name', 'displayName', 'dataSourceId', 'destinationDatasetId',
                                                'schedule', 'scheduleOptions', 'scheduleOptionsV2', 'disabled') if k in config}
                self.manifest['transfers'].append(record)
                if config.get('dataSourceId') == 'scheduled_query':
                    params = config.get('params', {})
                    identifier = config['name'].split('/')[-1]
                    base = Path('scheduled_queries') / location / (safe_name(config.get('displayName', identifier)) + '--' + identifier)
                    if params.get('query'):
                        self.write(base.with_suffix('.sql'), params['query'].replace('\r\n', '\n') + '\n',
                                   {'resource': config['name']})
                    record['query_parameters'] = {k: params[k] for k in ('destination_table_name_template',
                        'write_disposition', 'partitioning_field') if k in params}
                    self.write(base.with_suffix('.json'), json.dumps(record, indent=2) + '\n',
                               {'resource': config['name']})
        except Exception as exc:
            self.gap(parent + '/transferConfigs', exc)

    def run(self):
        datasets = bq(self.project, ['ls', '--all', '--max_results=1000000'])
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(self.dataset, datasets))
        locations = self.pages('dataform', f'projects/{self.project}/locations', 'locations', {'pageSize': 100})
        names = sorted({x['locationId'] for x in locations})
        with ThreadPoolExecutor(max_workers=6) as pool:
            groups = list(pool.map(self.location, names))
        # Transfer locations API does not accept pageSize; use its own advertised locations.
        try:
            transfer_locations = self.pages('bigquerydatatransfer', f'projects/{self.project}/locations', 'locations')
            transfer_names = sorted({x['locationId'] for x in transfer_locations})
        except Exception as exc:
            self.gap('transfer location discovery', exc)
            transfer_names = sorted({x['location'] for x in datasets} | {'us', 'eu'})
        self.manifest['transfer_locations_checked'] = transfer_names
        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(self.transfers, transfer_names))
            list(pool.map(self.repository, [r for group in groups for r in group]))
        self.manifest['completed_at'] = datetime.now(timezone.utc).isoformat()
        for key in ('datasets', 'repositories', 'transfers', 'coverage', 'gaps', 'files'):
            self.manifest[key].sort(key=lambda row: json.dumps(row, sort_keys=True))
        (self.output / 'manifest.json').write_text(json.dumps(self.manifest, indent=2) + '\n', encoding='utf-8')
        print('COMPLETE', len(self.manifest['files']), 'files;', len(self.manifest['gaps']), 'gaps', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9-]+', args.project):
        parser.error('Invalid project ID')
    args.output.mkdir(parents=True, exist_ok=False)
    Exporter(args.project, args.output).run()


if __name__ == '__main__':
    main()
