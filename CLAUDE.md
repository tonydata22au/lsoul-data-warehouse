@AGENTS.md

## Claude Code

- The shared project guide above (`AGENTS.md`) is the source of truth; put changes that apply
  to every agent there, not here.
- Skills: `.claude/skills/<name>` are symlinks to `.agents/skills/<name>`. Edit the canonical
  file under `.agents/skills/`; Edit/Write refuse to write through the symlink anyway.
- `.claude/settings.json` denies reading `.env` and `credentials/`, and asks before `gcloud`, `bq`,
  `docker push`, `git push`, `gunicorn`/`flask`, or running Python scripts under `src/`. Don't
  route around these rules (for example with `cat`, `env`, or a wrapper script); ask the user instead.
- Prefer delegating broad code searches across `src/` (90+ near-duplicate scripts) to a
  subagent and report the conclusion.
