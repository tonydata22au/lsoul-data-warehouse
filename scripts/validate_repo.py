#!/usr/bin/env python3
"""Offline repository checks for the LSOUL data warehouse.

Safe to run anywhere: no network calls, no source-system API calls, no BigQuery
access. The static checks use only the standard library.

Usage:
    python3 scripts/validate_repo.py              # static checks
    .venv/bin/python scripts/validate_repo.py --imports
        # also imports every Cloud Run service (needs pipeline dependencies) in
        # an isolated subprocess: dotenv loading disabled, dummy credentials,
        # temporary HOME (no gcloud/ADC files) and sockets blocked

Exit status is 1 when any check fails. Warnings do not fail the run.
"""
import argparse
import ast
import json
import os
import re
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
CLOUD_RUN = SRC / "cloud_run"
SKILLS = ROOT / ".agents" / "skills"
CLAUDE_SKILLS = ROOT / ".claude" / "skills"
INVENTORY = ROOT / "docs" / "pipelines.md"
SKIP_DIRS = {".venv", ".git", "credentials", "seeds", "data", "node_modules", "__pycache__"}

# Pre-existing defects that are documented rather than fixed (see docs/troubleshooting.md).
# Each entry: (description, text that must appear in the expected import error).
KNOWN_BROKEN_SERVICES = {
    "cloud-run-tiktok-thai-ads": (
        "app_runner.py loads cr-tiktok-thai-ads.py but the folder contains cr-tiktok-ads.py",
        "No such file or directory: '{service}/cr-tiktok-thai-ads.py'",
    ),
}

# Every credential the pipelines read from the environment (see .env.example).
CREDENTIAL_ENV_VARS = [
    "DIANPLUS_APP_KEY", "DIANPLUS_APP_SECRET", "DIANPLUS_TOKEN",
    "JUSHUITAN_APP_KEY", "JUSHUITAN_APP_SECRET",
    "MAGENTO_USERNAME", "MAGENTO_PASSWORD",
    "META_ACCESS_TOKEN", "META_ACCESS_TOKEN_LOCAL",
    "PANCAKE_API_KEY", "SURFOSM_API_KEY",
    "TIKTOK_ACCESS_TOKEN", "TIKTOK_VN_ACCESS_TOKEN", "TIKTOK_TH_ACCESS_TOKEN",
]

CREDENTIAL_NAME = re.compile(r"(?i)(api_?key|app_?key|app_?secret|secret|token|password|passwd|access-token|x-api-key)")
NOT_CREDENTIAL_NAME = re.compile(r"(?i)(_cached_token|_token_expiry|token_url|expire)")


def iter_files(base, pattern):
    for path in sorted(base.rglob(pattern)):
        if not SKIP_DIRS & set(path.relative_to(ROOT).parts):
            yield path


def rel(path):
    return path.relative_to(ROOT).as_posix()


def parse(path):
    """Parse a file without executing it; ignore escape-sequence warnings from existing docstrings."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", (SyntaxWarning, DeprecationWarning))
        return ast.parse(path.read_text(encoding="utf-8"), filename=str(path))


def check_python_syntax():
    errors = []
    for base in (SRC, ROOT / "scripts", ROOT / "tests"):
        for path in iter_files(base, "*.py"):
            try:
                parse(path)
            except SyntaxError as exc:
                errors.append(f"{rel(path)}:{exc.lineno}: {exc.msg}")
    return errors, []


def check_cloud_run_services():
    errors, warnings = [], []
    for service in sorted(p for p in CLOUD_RUN.iterdir() if p.is_dir()):
        for required in ("Dockerfile", "requirements.txt", "app_runner.py"):
            if not (service / required).is_file():
                errors.append(f"{rel(service)}: missing {required}")
        runner = service / "app_runner.py"
        if not runner.is_file():
            continue
        targets = re.findall(r'with_name\("([^"]+)"\)', runner.read_text(encoding="utf-8"))
        missing = [t for t in targets if not (service / t).is_file()]
        if service.name in KNOWN_BROKEN_SERVICES:
            if missing:
                warnings.append(f"{rel(service)}: known issue: {KNOWN_BROKEN_SERVICES[service.name][0]}")
            else:
                warnings.append(f"{rel(service)}: known issue appears fixed; remove it from KNOWN_BROKEN_SERVICES")
        elif missing:
            errors.append(f"{rel(runner)}: loads missing file(s) {missing}")
        elif not targets:
            errors.append(f"{rel(runner)}: no with_name(...) module target found")
    return errors, warnings


def _is_env_call(node):
    func = getattr(node, "func", None)
    return isinstance(node, ast.Call) and isinstance(func, ast.Attribute) and (
        func.attr == "getenv"
        or (func.attr == "get" and isinstance(func.value, ast.Attribute) and func.value.attr == "environ")
    )


def _looks_secret(name, value):
    if not isinstance(value, str) or " " in value or "://" in value:
        return False
    if value.startswith(("/", "~", ".")) or "\\" in value or value.endswith((".json", ".py", ".txt")):
        return False  # file paths, not credentials
    if re.search(r"(?i)pass(word|wd)?$", name):
        return len(value) >= 6  # passwords can be purely alphabetic
    return len(value) >= 12 and bool(re.search(r"\d", value)) and bool(re.search(r"[A-Za-z]", value))


def _env_default(call):
    if len(call.args) >= 2:
        return call.args[1]
    return next((k.value for k in call.keywords if k.arg in ("default", "failobj")), None)


def _python_sources(base):
    """Yield (label, source) for .py files, extensionless Python scripts and notebook code cells."""
    for path in iter_files(base, "*"):
        if not path.is_file() or path.name.startswith("."):
            continue  # skips .DS_Store, .gitkeep
        if path.suffix == ".py" or (path.suffix == "" and path.name != "Dockerfile"):
            yield rel(path), path.read_text(encoding="utf-8", errors="ignore")
        elif path.suffix == ".ipynb":
            try:
                cells = json.loads(path.read_text(encoding="utf-8")).get("cells", [])
            except ValueError:
                continue
            for index, cell in enumerate(cells):
                if cell.get("cell_type") == "code":
                    source = cell.get("source", "")
                    yield f"{rel(path)}#cell{index}", "".join(source) if isinstance(source, list) else source


def check_no_hardcoded_credentials():
    """Fail on string literals assigned to credential-like names (or used as env defaults).

    A guardrail for the common patterns in this repo, not a complete secret scanner.
    """
    errors = []
    for base in (SRC, ROOT / "scripts", ROOT / "notebooks"):
        for label, source in _python_sources(base):
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", (SyntaxWarning, DeprecationWarning))
                    tree = ast.parse(source)
            except (SyntaxError, ValueError):
                continue  # not Python (e.g. notebook magics, binary files)
            for node in ast.walk(tree):
                pairs = []
                if isinstance(node, (ast.Assign, ast.AnnAssign)) and node.value is not None:
                    targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                    for target in targets:
                        name = getattr(target, "id", getattr(target, "attr", ""))
                        pairs.append((name, node.value))
                elif isinstance(node, ast.Dict):
                    for key, value in zip(node.keys, node.values):
                        if isinstance(key, ast.Constant) and isinstance(key.value, str):
                            pairs.append((key.value, value))
                for name, value in pairs:
                    if not CREDENTIAL_NAME.search(name) or NOT_CREDENTIAL_NAME.search(name):
                        continue
                    if _is_env_call(value):
                        value = _env_default(value)
                    if isinstance(value, ast.Constant) and _looks_secret(name, value.value):
                        errors.append(f"{label}:{value.lineno}: literal assigned to {name!r}; read it from os.environ instead")
    return errors, []


LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def check_markdown_links():
    errors = []
    md_files = [p for p in iter_files(ROOT, "*.md")]
    for path in md_files:
        text = path.read_text(encoding="utf-8")
        text = re.sub(r"```.*?```", "", text, flags=re.S)  # ignore fenced code
        for target in LINK.findall(text):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
                continue
            target_path = target.split("#", 1)[0]
            if not target_path:
                continue
            resolved = (path.parent / target_path).resolve()
            if not resolved.exists():
                errors.append(f"{rel(path)}: broken link -> {target}")
    return errors, []


def _frontmatter(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    fields = {}
    for line in text[4:end].splitlines():
        if ":" in line and not line.startswith((" ", "\t")):
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    return fields


def check_skills():
    errors = []
    if not SKILLS.is_dir():
        return [f"{rel(SKILLS)} missing"], []
    canonical = sorted(p for p in SKILLS.iterdir() if p.is_dir())
    for skill in canonical:
        skill_md = skill / "SKILL.md"
        if not skill_md.is_file():
            errors.append(f"{rel(skill)}: missing SKILL.md")
            continue
        fields = _frontmatter(skill_md.read_text(encoding="utf-8"))
        if fields is None:
            errors.append(f"{rel(skill_md)}: frontmatter must start on line 1 with ---")
            continue
        name, description = fields.get("name", ""), fields.get("description", "")
        if name != skill.name:
            errors.append(f"{rel(skill_md)}: name {name!r} must equal directory name {skill.name!r}")
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name or "-") or len(name) > 64:
            errors.append(f"{rel(skill_md)}: name must be lowercase letters, digits and hyphens (max 64)")
        if not description or len(description) > 1024:
            errors.append(f"{rel(skill_md)}: description is required and must be at most 1024 characters")
        claude_entry = CLAUDE_SKILLS / skill.name
        if not (claude_entry / "SKILL.md").is_file():
            errors.append(f"{rel(claude_entry)}: missing; link it to ../../.agents/skills/{skill.name}")
        elif (claude_entry / "SKILL.md").resolve() != skill_md.resolve():
            errors.append(f"{rel(claude_entry)}: must be a symlink to the canonical skill, not a copy")
    if CLAUDE_SKILLS.is_dir():
        for entry in CLAUDE_SKILLS.iterdir():
            if not (SKILLS / entry.name).is_dir():
                errors.append(f"{rel(entry)}: no matching canonical skill in {rel(SKILLS)}")
    return errors, []


def check_agent_docs():
    errors = []
    agents, claude = ROOT / "AGENTS.md", ROOT / "CLAUDE.md"
    if not agents.is_file():
        errors.append("AGENTS.md missing")
    elif agents.stat().st_size > 32 * 1024:
        errors.append("AGENTS.md exceeds Codex's default 32 KiB project_doc_max_bytes")
    if not claude.is_file() or "@AGENTS.md" not in claude.read_text(encoding="utf-8").splitlines():
        errors.append("CLAUDE.md must contain an '@AGENTS.md' import line")
    return errors, []


def check_pipeline_inventory():
    errors = []
    if not INVENTORY.is_file():
        return [f"{rel(INVENTORY)} missing"], []
    text = INVENTORY.read_text(encoding="utf-8")
    entries = [p.name for p in CLOUD_RUN.iterdir() if p.is_dir()]
    for folder in ("local_run", "csv_export", "schema"):
        entries += [p.name for p in (SRC / folder).iterdir() if p.is_file() and p.name != ".DS_Store"]
    for name in sorted(entries):
        if name not in text:
            errors.append(f"{rel(INVENTORY)}: no entry for {name}")
    return errors, []


def check_git_hygiene():
    warnings = []
    try:
        clean = subprocess.run(["git", "config", "filter.nbstrip.clean"], cwd=ROOT,
                               capture_output=True, text=True).stdout.strip()
    except OSError:
        return [], ["git not available; skipped notebook filter check"]
    if not clean:
        warnings.append("notebook output filter not configured; run the git config commands in docs/setup.md")
    return [], warnings


# Runs inside each service folder. Blocks sockets and disables dotenv before importing.
IMPORT_SMOKE_CODE = """
import socket

def _blocked(*args, **kwargs):
    raise RuntimeError("network access attempted during import")

socket.socket.connect = socket.socket.connect_ex = _blocked
socket.create_connection = socket.getaddrinfo = _blocked

import dotenv, dotenv.main
dotenv.load_dotenv = dotenv.main.load_dotenv = lambda *args, **kwargs: False

import app_runner
assert app_runner.app is not None
"""


def check_service_imports(services=None):
    """Import each Cloud Run service the way gunicorn does, isolated from real credentials and the network."""
    errors, warnings = [], []
    if services is None:
        services = sorted(p for p in CLOUD_RUN.iterdir() if p.is_dir())
    with tempfile.TemporaryDirectory() as home:
        # Minimal environment: no GOOGLE_APPLICATION_CREDENTIALS, no real tokens, and a
        # temporary HOME/CLOUDSDK_CONFIG so Application Default Credentials can't be found.
        env = {key: os.environ[key] for key in ("PATH", "LANG", "SYSTEMROOT") if key in os.environ}
        env.update({"HOME": home, "CLOUDSDK_CONFIG": home, "PYTHONDONTWRITEBYTECODE": "1"})
        env.update({name: "dummy" for name in CREDENTIAL_ENV_VARS})
        for service in services:
            result = subprocess.run([sys.executable, "-c", IMPORT_SMOKE_CODE], cwd=service, env=env,
                                    capture_output=True, text=True, timeout=120)
            if result.returncode == 0:
                continue
            last = (result.stderr.strip().splitlines() or ["unknown error"])[-1]
            label = rel(service) if ROOT in service.parents else service.name
            known = KNOWN_BROKEN_SERVICES.get(service.name)
            if known and known[1].format(service=service) in last:
                warnings.append(f"{label}: known issue: {known[0]}")
            else:
                errors.append(f"{label}: import failed: {last}")
    return errors, warnings


STATIC_CHECKS = [
    check_python_syntax,
    check_cloud_run_services,
    check_no_hardcoded_credentials,
    check_markdown_links,
    check_skills,
    check_agent_docs,
    check_pipeline_inventory,
    check_git_hygiene,
]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--imports", action="store_true",
                        help="also import every Cloud Run service (needs pipeline dependencies)")
    args = parser.parse_args(argv)
    checks = STATIC_CHECKS + ([check_service_imports] if args.imports else [])
    failed = False
    for check in checks:
        errors, warnings = check()
        status = "FAIL" if errors else "PASS"
        failed = failed or bool(errors)
        print(f"{status} {check.__name__}")
        for message in errors:
            print(f"  error: {message}")
        for message in warnings:
            print(f"  warn:  {message}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
