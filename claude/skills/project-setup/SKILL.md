---
name: project-setup
description: >-
  Initialize Python projects with standard configuration files
  (.markdownlint.json, tox.ini, pyproject.toml). Use when starting new Python
  projects or standardizing existing ones.
allowed-tools: Write, Bash, Read, Glob
---

# project-setup

## Help

If args is `-h` / `--help` / `help`, read `references/help.md` verbatim and stop.

## Role & Purpose

Python project configuration specialist. Generates the three standard
config files (`.markdownlint.json`, `tox.ini`, `pyproject.toml`) with
project-specific placeholders resolved from git config and the directory name.

## Trigger Scenarios

- "Initialize Python project configuration"
- "Set up a new Python project"
- "Create standard config files for Python"
- "프로젝트 초기 설정 파일 생성해"
- "Python 프로젝트 환경 구축해"
- "tox.ini, pyproject.toml 생성해줘"

## Options

See `references/options.md` for the full flag table — `PROJECT_NAME`
override, `--force`, `--dry-run`, `-h`/`--help`/`help`.

## Workflow (stop on first failure — any Step failure halts the chain)

1. **Step 1 Discover** — read repo state, detect existing configs, extract
   git author info. See `references/phases-detail.md` → Step 1.
2. **Step 2 Plan** — propose which templates apply, what gets backed up,
   placeholder values. If `--dry-run`, stop here. See `references/phases-detail.md` → Step 2.
3. **Step 3 Backup** — copy existing files to `.bak.<timestamp>`.
   See `references/phases-detail.md` → Step 3.
4. **Step 4 Apply Templates** — write the three templates with placeholders
   resolved. Templates live in `references/templates.md` (single SSOT —
   no duplication).
5. **Step 5 Validate** — verify JSON / INI / TOML parses and no `{{...}}`
   placeholders remain. See `references/phases-detail.md` → Step 5.
6. **Step 6 Report** — emit verdict + next-action hint.

Error / degradation branches: see `references/error-handling.md`.

## Output

Success:

```
[OK] project-setup — <n> files created, <m> backed up
  files:
    .markdownlint.json
    tox.ini
    pyproject.toml
  validation: <n> linters passed

Next: tox -e ruff && tox -e mypy
```

Failure:

```
[FAIL] project-setup — Step <n>: <reason>
```

## References

- `references/help.md` — verbatim usage on `-h` / `--help` / `help`
- `references/options.md` — option / flag table
- `references/phases-detail.md` — Step 1–5 detailed instructions
- `references/templates.md` — `.markdownlint.json` / `tox.ini` / `pyproject.toml` (single SSOT)
- `references/error-handling.md` — graceful degradation branches
- `references/example.md` — real-world before / after
