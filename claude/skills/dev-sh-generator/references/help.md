# dev-sh-generator — Help

## Synopsis

```
dev-sh-generator
```

Generate or regenerate a project-specific `tools/dev.sh` task runner that
follows the patterns defined in `tools/AGENTS.md` (the SSOT for this skill).

## Description

Analyzes the current Python/FastAPI/Django project, extracts the configuration
required to drive a `tools/dev.sh` task runner, picks the matching template,
and writes an executable `tools/dev.sh` to the repo. The generator is strict
about the AGENTS.md golden rules — in particular, NO EMOJIS anywhere in the
generated script.

## Options / Configuration variables

See `references/options.md` for the full env-var and configuration-variable
reference table (`PY_RUN`, `PY_TEST`, `UVICORN_ENTRY`, `USE_ALEMBIC`,
`IS_DJANGO`, `MANAGE_PY`, `DEFAULT_DATASET`, `CLI_ENTRY`, plus runtime
overrides `APP_ENV`, `DATASET`, `DJANGO_SETTINGS_MODULE`).

## Workflow

1. Analyze project — read `tools/AGENTS.md`, `pyproject.toml`, scan structure.
   See `references/preflight-and-analysis.md`.
2. Generate `tools/dev.sh` using the matching template (T1/T2/T3).
   See `references/generation-protocol.md` and `references/templates.md`.
3. Validate against quality gates (no emojis, executable, syntax-clean).
   See `references/generation-protocol.md`.
4. Report verdict with template choice + applied configuration.

Stops on first failure — any phase failure halts the chain.

## Examples

```bash
# Run inside a project root that has tools/AGENTS.md
./tools/dev.sh help            # exercise the generated script after run
./tools/dev.sh up              # start dev server
./tools/dev.sh test -k api     # forward args to pytest
DATASET=/data ./tools/dev.sh up
```

## Stop conditions

- Missing `tools/AGENTS.md` → warn, fall back to detected defaults.
  See `references/error-handling.md`.
- No detectable server entry point → write `up` with an actionable error.
- Permission issues on `tools/` → display content for manual creation.
- Emojis present in any pre-existing file → strip and notify user.

## See also

- `references/options.md` — configuration variable reference
- `references/templates.md` — T1 (FastAPI+uv), T2 (Django+poetry), T3 (FastAPI+alembic)
- `references/linting-strategy.md` — why `lint` is split from `mdlint`
- `references/examples.md` — before/after, scope boundaries
- `tools/AGENTS.md` — SSOT for the generated commands and conventions
