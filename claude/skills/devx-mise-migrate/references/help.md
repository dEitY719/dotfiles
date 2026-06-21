# devx:mise-migrate — Help

## Usage

```
/devx:mise-migrate [path] [flags]
/devx-mise-migrate ~/para/project/karakeep/sync          # dry-run plan
/devx-mise-migrate ~/para/project/karakeep/sync --apply  # write + uv sync
/devx:mise-migrate -h        # show this help
/devx:mise-migrate --help    # show this help
/devx:mise-migrate help      # show this help
```

## Arguments

| # | Name | Required | Description |
|---|------|----------|-------------|
| 1 | `[path]` | no | Target project directory. Defaults to `.` (cwd). |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | **on** | Default. Prints the migration plan; writes nothing. |
| `--apply` | off | Writes `mise.toml`, rewrites `pyproject.toml`, runs `uv sync`, then cleans up. |
| `--backend <name>` | `hatchling` | Build backend to modernize toward: `hatchling` or `uv_build`. |
| `--keep-venv` | off | Skip the cleanup step — leave the old `.venv/` and `*.egg-info/` in place. |

## Examples

```
# 1. Inspect the plan for the current dir (no writes):
/devx-mise-migrate

# 2. Plan a specific project:
/devx-mise-migrate ~/para/project/karakeep/sync

# 3. Apply — write mise.toml, rewrite pyproject, uv sync, clean up:
/devx-mise-migrate ~/para/project/karakeep/sync --apply

# 4. Apply but keep the old venv/egg-info, and use uv's own backend:
/devx-mise-migrate . --apply --backend uv_build --keep-venv
```

## What the skill does

1. **Detects** a legacy Python project (pyproject / setup.py /
   requirements + a pyenv-style `.venv`) and refuses non-Python or
   already-migrated (`mise.toml` present) directories.
2. **Extracts** the Python version, runtime + dev deps, `[project.scripts]`
   entry points, test runner/`testpaths`, and current build backend.
3. **Plans** three artifacts: the generated `mise.toml`, a
   `pyproject.toml` diff, and the cleanup list. In dry-run this is the
   single review surface — nothing is written.
4. **`--apply` only** — writes `mise.toml`, rewrites `pyproject.toml`
   (backend → hatchling, `optional-dependencies.dev` →
   `[dependency-groups].dev`), runs `uv sync`, and removes the stale
   `.venv/` + `*.egg-info/`.

## What the skill will NOT do

- Touch non-Python projects, or migrate node/go/etc. — Python-venv scope
  only by design.
- Re-migrate a project that already has a `mise.toml` (idempotent no-op).
- Generate lint/fix tasks for tools the project does not use — a missing
  linter is logged, not silently added.
- Rewrite source code or change import paths — only `mise.toml` and the
  build/dependency stanzas of `pyproject.toml`.
- Delete anything outside the target `<path>`, or delete the old venv
  when `--keep-venv` is set.
- Roll back a partial `--apply` failure — it reports partial state and
  stops; the user owns cleanup.

## Prerequisites

- `uv` and `mise` available on `PATH` (the generated `[tools]` pins both,
  but `--apply` calls `uv sync` directly).
- Write access to `<path>` for `--apply`.

## Pairs with

- `mise run lint|test|fix` — the workflow this skill bootstraps. After a
  successful apply, start with `mise run test`.
