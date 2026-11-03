#!/usr/bin/env python3
"""Build metadata/pipeline_manifest.json: a static index of every Python pipeline.

Offline and read-only: parses source with `ast` (never imports a pipeline), reads
docs/pipelines.md, makes no network or BigQuery calls. For each pipeline file the
manifest records its variant, service, source system, destination tables (with the
evidence for each), write dispositions, the *names* of environment variables it reads,
and its functions/classes with line ranges. Agents and the LSOUL MCP server use it to
link pipelines to raw tables without reading whole files.

Usage:
    python3 scripts/build_pipeline_manifest.py           # write the manifest
    python3 scripts/build_pipeline_manifest.py --check   # exit 1 if it is missing or stale
"""
import argparse
import ast
import json
import re
import sys
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = Path("metadata") / "pipeline_manifest.json"
GENERATOR = "scripts/build_pipeline_manifest.py"
VARIANTS = ("cloud_run", "local_run", "csv_export", "schema")
NOT_PIPELINES = {"app_runner.py", "__init__.py"}
SOURCE_SYSTEMS = ("pancake", "dianplus", "jushuitan", "magento", "surfosm", "tiktok", "meta")
DOC_DESTINATION_COLUMNS = ("destination", "creates")
DOC_SOURCE_COLUMNS = ("source endpoint", "source")

DATASET_NAME = re.compile(r"(^|_)DATASET(_ID|_NAME)?$")
TABLE_NAME = re.compile(r"(^|_)TABLE(_ID|_NAME)?$")
IDENTIFIER = re.compile(r"^[A-Za-z_][\w-]*$")
RELATION = re.compile(r"^[A-Za-z_][\w-]*(\.[A-Za-z_*][\w*-]*){1,2}$")
ENV_DEFAULT = re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*:-([^}]*)\}")
MAX_DOC = 160


def _relation(value):
    """`project.dataset.table` or `dataset.table` -> `dataset.table`; anything else -> None."""
    value = ENV_DEFAULT.sub(lambda m: m.group(1), value.strip())
    if not RELATION.match(value):
        return None
    return ".".join(value.split(".")[-2:])


def _cells(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def doc_rows(root):
    """Map a pipelines.md row key (service folder or file name) to the tables in its
    Destination/Creates column and the text of its Source column."""
    path = root / "docs" / "pipelines.md"
    if not path.is_file():
        return {}
    lines = path.read_text(encoding="utf-8").splitlines()
    found = {}
    column = source = None
    for i, line in enumerate(lines):
        if not line.lstrip().startswith("|"):
            column = source = None
            continue
        cells = _cells(line)
        if i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            names = [c.lower() for c in cells]
            column = next((names.index(n) for n in DOC_DESTINATION_COLUMNS if n in names), None)
            source = next((names.index(n) for n in DOC_SOURCE_COLUMNS if n in names), None)
            continue
        key = cells[0].strip("`* ")
        if not key or re.match(r"^[\s:|-]+$", line):
            continue
        row = found.setdefault(key, {"source": "", "tables": []})
        if source is not None and source < len(cells):
            row["source"] = row["source"] or cells[source]
        if column is not None and column < len(cells):
            tokens = re.findall(r"`([^`]+)`", cells[column])
            row["tables"] += [t for t in map(_relation, tokens) if t and t not in row["tables"]]
    return found


def _parse(path):
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", (SyntaxWarning, DeprecationWarning))
        return ast.parse(path.read_text(encoding="utf-8"), filename=str(path))


def _is_environ(node):
    return (isinstance(node, ast.Attribute) and node.attr == "environ") or (
        isinstance(node, ast.Name) and node.id == "environ")


def _env_call(node):
    """Return the variable name for os.getenv("X", ...) / os.environ.get("X", ...)."""
    if not isinstance(node, ast.Call) or not node.args:
        return None
    func = node.func
    is_getenv = (isinstance(func, ast.Attribute) and func.attr == "getenv") or (
        isinstance(func, ast.Name) and func.id == "getenv")
    is_environ_get = isinstance(func, ast.Attribute) and func.attr == "get" and _is_environ(func.value)
    first = node.args[0]
    if (is_getenv or is_environ_get) and isinstance(first, ast.Constant) and isinstance(first.value, str):
        return first.value
    return None


def _string_value(node):
    """A literal string, or the literal default of an env lookup."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if _env_call(node) and len(node.args) > 1:
        return _string_value(node.args[1])
    return None


def env_vars(tree):
    names = set()
    for node in ast.walk(tree):
        name = _env_call(node)
        if name is None and isinstance(node, ast.Subscript) and _is_environ(node.value):
            key = node.slice
            if isinstance(key, ast.Constant) and isinstance(key.value, str):
                name = key.value
        if name and re.match(r"^[A-Z][A-Z0-9_]*$", name):
            names.add(name)
    return sorted(names)


def write_dispositions(tree):
    found = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute) and node.attr.startswith("WRITE_"):
            found.add(node.attr)
        elif isinstance(node, ast.Constant) and node.value in ("WRITE_APPEND", "WRITE_TRUNCATE", "WRITE_EMPTY"):
            found.add(node.value)
    return sorted(found)


def code_destinations(tree):
    """Destination tables from DATASET_*/TABLE_* constants and dataset_id/table_id defaults."""
    datasets, tables = [], []

    def note(name, value, line):
        if value is None or not (IDENTIFIER.match(value) or _relation(value)):
            return
        upper = name.upper()
        if DATASET_NAME.search(upper):
            datasets.append(value)
        elif TABLE_NAME.search(upper):
            tables.append((value, line))

    for node in tree.body:
        targets = node.targets if isinstance(node, ast.Assign) else (
            [node.target] if isinstance(node, ast.AnnAssign) and node.value else [])
        for target in targets:
            if isinstance(target, ast.Name):
                note(target.id, _string_value(node.value), node.lineno)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            args = node.args.args + node.args.kwonlyargs
            defaults = [None] * (len(node.args.args) - len(node.args.defaults)) + node.args.defaults
            defaults += node.args.kw_defaults
            for arg, default in zip(args, defaults):
                if default is not None:
                    note(arg.arg, _string_value(default), default.lineno)

    unique_datasets = sorted(set(datasets))
    found = []
    for value, line in tables:
        table = _relation(value)
        if table is None and len(unique_datasets) == 1:
            table = f"{unique_datasets[0]}.{value}"
        record = {"evidence": "code", "line": line, "table": table}
        if table is None:
            record["raw"] = value
        found.append(record)
    return found


def symbols(tree):
    found = []

    def add(node, kind, name):
        start = min([node.lineno] + [d.lineno for d in node.decorator_list])
        record = {"end_line": node.end_lineno, "kind": kind, "name": name, "start_line": start}
        doc = ast.get_docstring(node)
        if doc and doc.strip():
            record["doc"] = doc.strip().splitlines()[0][:MAX_DOC]
        found.append(record)

    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            add(node, "function", node.name)
        elif isinstance(node, ast.ClassDef):
            add(node, "class", node.name)
            for child in node.body:
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    add(child, "method", f"{node.name}.{child.name}")
    return found


def source_system(*texts):
    """First known source system named in the path, then the docs Source cell, then the
    destination tables."""
    for text in texts:
        tokens = set(re.split(r"[^a-z0-9]+", text.lower()))
        name = next((n for n in SOURCE_SYSTEMS if n in tokens), None)
        if name:
            return name
    return None


def pipeline_files(root):
    src = root / "src"
    for variant in VARIANTS:
        base = src / variant
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.py")):
            parts = path.relative_to(base).parts
            if path.name in NOT_PIPELINES or "__pycache__" in parts or path.name.startswith("test_"):
                continue
            yield variant, path


def describe(root, variant, path, docs):
    relative = path.relative_to(root).as_posix()
    service = path.relative_to(root / "src" / variant).parts[0] if variant == "cloud_run" else None
    doc_key = service if variant == "cloud_run" and path.name.startswith("cr-") else (
        None if variant == "cloud_run" else path.name)
    row = docs.get(doc_key) or docs.get(service) or {"source": "", "tables": []}
    destinations = [{"evidence": "docs/pipelines.md", "table": t}
                    for t in (row["tables"] if doc_key else [])]
    entry = {"path": relative, "service": service, "variant": variant}
    try:
        tree = _parse(path)
    except SyntaxError:
        tree = None
        entry.update(env_vars=[], parse_error=True, symbols=[], write_dispositions=[])
    else:
        destinations += code_destinations(tree)
        entry.update(env_vars=env_vars(tree), symbols=symbols(tree),
                     write_dispositions=write_dispositions(tree))
    destinations.sort(key=lambda d: (d.get("table") or "", d["evidence"], d.get("line", 0)))
    tables = " ".join(d["table"] for d in destinations if d.get("table"))
    entry.update(destinations=destinations,
                 source_system=source_system(relative, row["source"], tables))
    return entry


def build_manifest(root=ROOT):
    root = Path(root)
    docs = doc_rows(root)
    pipelines = [describe(root, variant, path, docs) for variant, path in pipeline_files(root)]
    pipelines.sort(key=lambda p: p["path"])
    return {"generator": GENERATOR, "pipelines": pipelines, "schema_version": 1}


def render(manifest):
    return json.dumps(manifest, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="exit 1 if the manifest is missing or stale")
    parser.add_argument("--root", default=str(ROOT), help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    root = Path(args.root)
    target = root / MANIFEST
    text = render(build_manifest(root))
    if args.check:
        if not target.is_file():
            print(f"{MANIFEST.as_posix()} is missing; run python3 {GENERATOR}")
            return 1
        if target.read_text(encoding="utf-8") != text:
            print(f"{MANIFEST.as_posix()} is stale; run python3 {GENERATOR}")
            return 1
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    print(f"wrote {MANIFEST.as_posix()} ({len(text.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
