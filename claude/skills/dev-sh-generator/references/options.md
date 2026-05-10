# Configuration variable reference table

These variables drive template generation. `tools/AGENTS.md` is the SSOT —
values declared there override any heuristic detection. Phase 0–1
(`references/preflight-and-analysis.md`) builds this map; Phase 2
(`references/generation-protocol.md`) writes the values into `tools/dev.sh`.

## Generator-side variables (baked into tools/dev.sh)

| Option | Description | Default |
| --- | --- | --- |
| `PY_RUN` | Python execution command driving every subcommand. | `uv run` if `uv.lock`; `poetry run` if `poetry.lock`; else `python` |
| `PY_TEST` | Full test invocation, including `-q`. Receives forwarded args via `"${@:2}"`. | `$PY_RUN pytest -q` |
| `UVICORN_ENTRY` | FastAPI/Uvicorn import path, e.g. `src.backend.main:app`. Empty disables the `up` server path. | `""` (forces actionable error if empty) |
| `USE_ALEMBIC` | When `true`, `up` runs `alembic upgrade head` before uvicorn. | `false` |
| `IS_DJANGO` | When `true`, `up` runs `manage.py migrate` + `manage.py runserver`. | `false` |
| `MANAGE_PY` | Path to Django `manage.py`. Only used when `IS_DJANGO=true`. | `manage.py` |
| `DEFAULT_DATASET` | Default dataset path exported as `DATASET` for the FastAPI `up` path. | `./data` (T1 hardcoded — see SKILL.md Known risks) |
| `CLI_ENTRY` | Path to interactive CLI script. Empty omits the `cli` subcommand entirely. | `src/backend/cli/app.py` for T1, `""` for T2/T3 |

## Runtime overrides (set by the user when invoking tools/dev.sh)

| Override | Description | Default |
| --- | --- | --- |
| `APP_ENV` | Selects FastAPI runtime profile. Exported only by the `up` path. | `development` |
| `DATASET` | Overrides `DEFAULT_DATASET` for a single `up` invocation. | value of `DEFAULT_DATASET` |
| `DJANGO_SETTINGS_MODULE` | Selects Django settings module for `up`. Exported only when `IS_DJANGO=true`. | `config.settings.dev` |

## Forwarding rule

The generator must emit `"${@:2}"` (not `$@`) for `test`, `cli`, and `mdlint`
so that the leading subcommand is stripped before forwarding. See
`references/generation-protocol.md` → "Command Implementation Rules".
