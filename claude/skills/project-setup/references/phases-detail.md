# project-setup — Step Details

Each step halts the chain on failure (`[FAIL]` verdict, no silent continuation).

## Step 1 — Discover

Read repo state and detect existing configs. Execute BEFORE creating anything.

1. **Verify current directory**

   ```bash
   pwd
   ls -la
   ```

2. **Check existing configuration**

   - Scan for existing `.markdownlint.json`, `tox.ini`, `pyproject.toml`.
   - Identify conflicts and backup needs.
   - Determine project name from directory (or argv override).

3. **Extract git configuration**

   ```bash
   git config user.name
   git config user.email
   ```

   If missing → see `references/error-handling.md` → Missing `Git` Configuration.

**Output:** project context, git config values, list of pre-existing files.

## Step 2 — Plan

Propose changes before touching disk.

- Which of the three templates apply (always all three unless `--force` is off
  and the file is identical to the template).
- What gets backed up (every existing file gets a `.bak.<timestamp>` copy).
- Placeholder values to substitute (`{{PROJECT_NAME}}`, `{{AUTHOR_NAME}}`,
  `{{AUTHOR_EMAIL}}`).
- Print the plan; if `--dry-run`, stop here with `[OK] project-setup — dry-run`.

## Step 3 — Backup

Run ONLY if files already exist (otherwise skip silently).

```bash
TS=$(python3 -c 'import datetime; print(datetime.datetime.now().strftime("%Y%m%d%H%M%S"))')
[ -f .markdownlint.json ] && cp .markdownlint.json ".markdownlint.json.bak.${TS}"
[ -f tox.ini ]            && cp tox.ini "tox.ini.bak.${TS}"
[ -f pyproject.toml ]     && cp pyproject.toml "pyproject.toml.bak.${TS}"
```

If any `cp` fails → halt with `[FAIL]` before any template write.

## Step 4 — Apply Templates

Write the three templates from `templates.md` in order:

1. `.markdownlint.json` — verbatim from `templates.md`.
2. `tox.ini` — verbatim from `templates.md`.
3. `pyproject.toml` — substitute placeholders:
   - `{{PROJECT_NAME}}` ← argv override or sanitized directory name.
   - `{{AUTHOR_NAME}}` ← `git config user.name` or `Your Name`.
   - `{{AUTHOR_EMAIL}}` ← `git config user.email` or `your.email@example.com`.

Templates live in `references/templates.md` — single SSOT, do not redeclare here.

## Step 5 — Validate

Verify each file before reporting success:

- `.markdownlint.json` parses as JSON (e.g. `python -m json.tool < .markdownlint.json`).
- `tox.ini` parses as INI (e.g. `python -c "import configparser; configparser.ConfigParser().read('tox.ini')"`).
- `pyproject.toml` parses as TOML — use the project's installed parser
  (Python 3.11+ ships `tomllib`; for 3.10 fall back to `tomli` via
  `python -c "import tomli; tomli.load(open('pyproject.toml','rb'))"`).
  This skill targets the project's declared minimum Python version, so do
  not hardcode `tomllib`.
- All `{{...}}` placeholders are gone from `pyproject.toml`.
- Files are readable (`test -r`).

Any failure → halt with `[FAIL]`, leave files in place, point user at backups.

## Step 6 — Report

Print the success verdict from the main `SKILL.md` Output section, then the
next-action hint: `Next: tox -e ruff && tox -e mypy`.
