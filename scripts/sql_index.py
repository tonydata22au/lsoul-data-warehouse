#!/usr/bin/env python3
"""Find the one editable file for a BigQuery object and compare it with the live snapshot.

Offline: reads files under sql/ only, never connects to BigQuery.

Every editable file under sql/staging, sql/core, sql/procedures and sql/functions is
named `<dataset>.<object>.sql` after the object it creates. sql/live/ is the
read-only, machine-generated snapshot of what is deployed; it is never edited by hand.

Usage:
    python3 scripts/sql_index.py                     # every object: editable path, live path, status
    python3 scripts/sql_index.py fn_sale_ecom_vn     # objects whose name contains the text
    python3 scripts/sql_index.py --drift             # only objects whose editable file differs from live
    python3 scripts/sql_index.py --check             # naming/uniqueness rules (exit 1 on violation)

Status: `same` (matches the live definition, ignoring comments, whitespace, case,
`OR REPLACE` and quoting), `differs` (edited here or changed in BigQuery since the
snapshot), `not deployed` (no live definition in the snapshot).
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYERS = ("staging", "core", "procedures", "functions")
LIVE = ROOT / "sql" / "live" / "bigquery"

# Files that deliberately define several objects; named after the group, not one object.
BUNDLES = {
    "sql/functions/reportdb.fn_money_helpers.sql":
        "reportdb.fn_money_scale, fn_money_unit, fn_fmt_money, fn_fmt_money_pair",
}

_NAME = r"`?([\w-]+)`?\s*\.\s*`?(\w+)`?\s*\.\s*`?(\w+)`?"
CREATE = re.compile(
    r"\bcreate\s+(?:or\s+replace\s+)?(?:temp(?:orary)?\s+)?"
    r"(?:table\s+function|aggregate\s+function|function|procedure|materialized\s+view|table|view)\s+"
    r"(?:if\s+not\s+exists\s+)?" + _NAME, re.I)
INSERT = re.compile(r"\binsert\s+(?:into\s+)?" + _NAME, re.I)
DATAFORM = re.compile(r"^\s*config\s*\{(.*?)\n\}", re.S)


def executable(sql):
    """SQL without comments, so commented-out statements are not mistaken for targets."""
    return re.sub(r"--[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", sql, flags=re.S))


def targets(sql):
    """`dataset.object` names a file creates, in order (Dataform config or INSERT as fallback)."""
    config = DATAFORM.match(sql)
    if config:
        name = re.search(r'\bname\s*:\s*"(\w+)"', config.group(1))
        dataset = re.search(r'\b(?:dataset|schema)\s*:\s*"(\w+)"', config.group(1))
        if name and dataset:
            return [f"{dataset.group(1)}.{name.group(1)}"]
    code = executable(sql)
    found = [f"{m.group(2)}.{m.group(3)}" for m in CREATE.finditer(code)]
    if not found:
        found = [f"{m.group(2)}.{m.group(3)}" for m in INSERT.finditer(code)][:1]
    return list(dict.fromkeys(found))


def normalise(sql):
    code = executable(sql).lower().replace("`", "")
    code = re.sub(r"\bcreate\s+or\s+replace\b", "create", code)
    return re.sub(r"\s+", "", code)


def rel(path, root):
    return path.relative_to(root).as_posix()


def live_path(obj, root=ROOT):
    dataset, name = obj.split(".", 1)
    for kind in ("routines", "tables"):
        path = root / "sql" / "live" / "bigquery" / dataset / kind / f"{name}.sql"
        if path.is_file():
            return path
    return None


def index(root=ROOT):
    rows = []
    for layer in LAYERS:
        for path in sorted((root / "sql" / layer).rglob("*.sql")):
            sql = path.read_text(encoding="utf-8")
            found = targets(sql)
            obj = found[0] if found else None
            live = live_path(obj, root) if obj else None
            if not live:
                status = "not deployed"
            elif normalise(sql) == normalise(live.read_text(encoding="utf-8")):
                status = "same"
            else:
                status = "differs"
            rows.append({"object": obj, "path": rel(path, root), "layer": layer,
                         "live": rel(live, root) if live else "", "status": status})
    return rows


def check(root=ROOT, rows=None):
    """Errors for nested folders, files not named after their object, or objects defined twice."""
    rows = index(root) if rows is None else rows
    errors, owners = [], {}
    for row in rows:
        path = row["path"]
        if path.count("/") != 2:
            errors.append(f"{path}: nested folder; keep editable SQL directly under sql/{row['layer']}/")
        if not row["object"]:
            errors.append(f"{path}: no CREATE, INSERT or Dataform config target found")
            continue
        expected = f"{row['object']}.sql"
        if path not in BUNDLES and Path(path).name != expected:
            errors.append(f"{path}: creates {row['object']}; rename it to {expected}")
        owners.setdefault(row["object"], []).append(path)
    for obj, paths in sorted(owners.items()):
        if len(paths) > 1:
            errors.append(f"{obj} is defined in more than one editable file: {', '.join(paths)}")
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("query", nargs="?", help="part of an object name, e.g. fn_sale_ecom_vn")
    parser.add_argument("--drift", action="store_true", help="only objects that differ from the live snapshot")
    parser.add_argument("--check", action="store_true", help="enforce naming and one file per object")
    args = parser.parse_args(argv)
    if args.check:
        rows = index()
        errors = check(rows=rows)
        for error in errors:
            print("error:", error)
        print(f"{len(rows)} editable files, {len(errors)} problems")
        return 1 if errors else 0
    rows = all_rows = index()
    if args.query:
        rows = [r for r in rows if args.query.lower() in (r["object"] or r["path"]).lower()]
    if args.drift:
        rows = [r for r in rows if r["status"] == "differs"]
    for row in rows:
        print(f"{row['status']:<13} {row['path']}")
        if row["live"]:
            print(f"{'':<13} live: {row['live']}")
    counts = {}
    for row in all_rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    print("\nall editable files: " + ", ".join(f"{n} {s}" for s, n in sorted(counts.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
