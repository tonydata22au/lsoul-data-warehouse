#!/usr/bin/env python3
"""Git clean filter: strip outputs from a Jupyter notebook read on stdin.

Notebook outputs in this repo contain LSOUL business results, so Git stores
notebooks without outputs while the working copy keeps them. Enable with:

    git config filter.nbstrip.clean "python3 scripts/nbstrip.py"
    git config filter.nbstrip.smudge cat
    git config filter.nbstrip.required true

Input that is not valid notebook JSON is passed through unchanged.
"""
import json
import sys


def strip(nb):
    for cell in nb.get("cells", []):
        if cell.get("cell_type") == "code":
            cell["outputs"] = []
            cell["execution_count"] = None
        cell.get("metadata", {}).pop("executionInfo", None)
        cell.get("metadata", {}).pop("execution", None)
    nb.get("metadata", {}).pop("widgets", None)
    return nb


def main():
    raw = sys.stdin.buffer.read()
    try:
        nb = json.loads(raw)
    except ValueError:
        sys.stdout.buffer.write(raw)
        return
    if not isinstance(nb, dict) or "cells" not in nb:
        sys.stdout.buffer.write(raw)
        return
    out = json.dumps(strip(nb), indent=1, ensure_ascii=False) + "\n"
    sys.stdout.buffer.write(out.encode("utf-8"))


if __name__ == "__main__":
    main()
