---
name: devx:mise-migrate
description: >-
  Convert a legacy Python project (pyenv / `python -m venv` + pip,
  setuptools, `.venv/bin/activate` workflow) into the dotfiles canonical
  mise structure: a `mise.toml` carrying `[tools]` + `[env]` + `[tasks.*]`
  as the command SSOT, with uv owning the venv and dependencies and
  hatchling as the build backend. Use when the user runs
  /devx:mise-migrate, /devx-mise-migrate, or asks "이 프로젝트 mise 구조로
  바꿔줘", "예전 파이썬 가상환경을 mise+uv 로 마이그레이션", "venv 프로젝트를
  mise 로 전환", "migrate this venv project to mise", "adopt mise here".
  Default mode is `--dry-run` — prints the migration plan (the full
  generated `mise.toml`, a `pyproject.toml` diff, the cleanup list, and a
  read-only scan for stale `venv`/`pip` references left in docs/scripts)
  and mutates nothing; `--apply` writes the files, runs `uv sync`, and
  removes the stale `.venv/` + `*.egg-info/` (add `--update-docs` to also
  rewrite the stale doc references). Warns when lifting dev deps to PEP
  735 `[dependency-groups]` silently breaks `pip install -e ".[dev]"`,
  and auto-retargets to a single nested project when the path has none.
  Python-venv projects only — refuses non-Python or already-migrated
  directories. Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Edit, Write, Grep
metadata:
  model_recommendation:
    tier: sonnet
    reason: "Config transformation + dependency/backend mapping; structured, low-ambiguity reasoning"
    claude: prefer
    non_claude: advisory-only
---

# devx:mise-migrate — legacy Python venv → mise + uv

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. **No detection, no file mutation.**

## Step 1: Parse Args + Detect a Legacy Python Project

Positional `[path]` defaults to `.`. Flags: `--dry-run` (default),
`--apply`, `--backend hatchling|uv_build` (default `hatchling`),
`--keep-venv`, `--update-docs`. Full table in `references/help.md`.

Detect a legacy Python project (pyproject / setup.py / `requirements*.txt`),
applying the nested-fallback retarget, the already-migrated short-circuit,
and the refusal exit codes in `references/detection.md`.

## Step 2: Extract Migration Facts (read-only)

Gather, via `Read` + `Grep`, the inputs in `references/extraction.md`:
Python version, runtime + dev deps, `[project.scripts]` entry points,
test runner + `testpaths`, build backend, and which linters (ruff /
mypy) are configured — lint/fix tasks are generated only for tools
actually present (Step 3).

## Step 3: Build the Migration Plan

Assemble four artifacts per `references/mise-template.md` and
`references/pyproject-rewrite.md` (`references/example-karakeep.md` is a
full before→after walkthrough):

1. **`mise.toml`** — `[tools]` (python + uv, + ruff/mypy if detected),
   `[env]`, `[tasks.lint|test|fix|run]` wrapping `uv run`. Mapping +
   linter-conditional rules: `references/mise-template.md`.
2. **`pyproject.toml` diff** — backend → `--backend`, explicit-packages
   carried over, `optional-dependencies.dev` → `[dependency-groups].dev`.
3. **Cleanup list** — stale `.venv/` + `*.egg-info/` (skipped by
   `--keep-venv`).
4. **Stale references** — read-only grep of `<path>` for the legacy
   `venv`/`pip`/`.[dev]` workflow, reported as `file:line` (history /
   archive excluded). Full ERE + opt-in `--update-docs` rewrite:
   `references/stale-scan.md`.

Surface the PEP 735 silent-regression `[WARN]` when a `dev` extra is
lifted (`references/pyproject-rewrite.md`), and the floor-vs-resolved
`[INFO]` when the pin came from `requires-python` (`references/extraction.md`).

In `--dry-run` (default), print all four and stop using the plan block in
`references/output-format.md`.

## Step 4: Apply (only if `--apply`)

In order, stopping on first failure with `[FAIL] devx:mise-migrate
<reason>` + exit 1 (no automatic rollback — report partial state):

1. Write `mise.toml`.
2. Rewrite `pyproject.toml` in place (backend, packages, dep-groups).
3. Run `uv sync` to materialize the uv-managed venv + lockfile.
4. Cleanup — remove `.venv/` + `*.egg-info/` unless `--keep-venv`;
   never delete outside `<path>`. Guardrails: `references/constraints.md`.
5. Stale docs — **only if `--update-docs`**, rewrite the non-excluded
   stale hits and re-print touched files (`references/stale-scan.md`).
   The PEP 735 `[WARN]` still fires (external CI is out of reach).

## Step 5: Report

Emit the success line, the `--apply` append fields, the dry-run `Next:`
hint, and the carried-over `[WARN]`/`[INFO]` notes per
`references/output-format.md`.
