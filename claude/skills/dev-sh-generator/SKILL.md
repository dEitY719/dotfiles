---
name: dev-sh-generator
description: >-
  Generate project-specific tools/dev.sh task runner following AGENTS.md
  standards. Use when creating or updating developer workflow automation scripts
  for Python/FastAPI projects.
allowed-tools: Read, Glob, Grep, Write, Bash, Edit
---

# dev-sh-generator

## Help

If args is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

## Role & Purpose

Development Workflow Automation Specialist. Generate standardized,
project-specific `tools/dev.sh` task runners that follow `tools/AGENTS.md` —
the SSOT for command shape, env vars, and conventions — so server, test,
format, shell, and CLI tasks behave consistently across projects.

## Trigger Scenarios

Use this skill when users request:

- "Create tools/dev.sh for this project"
- "Generate dev.sh script"
- "Set up developer task runner"
- "tools/dev.sh 생성해"
- "개발 스크립트 만들어줘"
- "Update tools/dev.sh to match AGENTS.md"

## Options

See `references/options.md` for the full env-var table
(`PY_RUN`, `PY_TEST`, `UVICORN_ENTRY`, `USE_ALEMBIC`, `IS_DJANGO`,
`MANAGE_PY`, `DEFAULT_DATASET`, `CLI_ENTRY`, plus runtime overrides
`APP_ENV`, `DATASET`, `DJANGO_SETTINGS_MODULE`).

## Workflow (stop on first failure — any phase failure halts the chain)

1. Analyze project — read `tools/AGENTS.md`, `pyproject.toml`, scan structure.
   See `references/preflight-and-analysis.md`. SSOT: `tools/AGENTS.md`.
2. Generate `tools/dev.sh` using the matching template (T1/T2/T3).
   See `references/generation-protocol.md`. Template choice rubric is in
   `references/templates.md` (uv.lock → T1, Django → T2, alembic.ini → T3).
3. Validate against quality gates — bash syntax, no emojis, executable,
   smoke tests. See `references/generation-protocol.md` → Phase 3.
4. Report verdict using the Output format below.

Error / degradation branches (missing AGENTS.md, no entry point, permission
issues, pre-existing emojis): see `references/error-handling.md`.

Linting layout (why `lint` is split from `mdlint`):
see `references/linting-strategy.md`.

## Output

Success:

```
[OK] tools/dev.sh generated
  template: <T1|T2|T3>
  applied: PY_RUN=<...>, PY_TEST=<...>, UVICORN_ENTRY=<...>, USE_ALEMBIC=<...>, CLI_ENTRY=<...>

Next: ./tools/dev.sh help
Then: ./tools/dev.sh up
```

Failure:

```
[FAIL] dev-sh-generator — Phase <n>: <reason>
```

## Known risks

Templates in `references/templates.md` carry through unchanged from the
previous SKILL.md revision. Two hardcoded T1 values remain:

- `DEFAULT_DATASET=./data`
- `CLI_ENTRY=src/backend/cli/app.py`

The generator must override both from `tools/AGENTS.md` (SSOT) when present.
Flagged for a follow-up issue — do not silently change template defaults in
this refactor PR.

## References

- `references/help.md` — verbatim usage block printed on `-h`/`--help`/`help`.
- `references/preflight-and-analysis.md` — Phase 0–1 analysis and config extraction.
- `references/generation-protocol.md` — Phase 2–4 generation, validation, quality gates, report.
- `references/templates.md` — T1/T2/T3 templates and selection rubric.
- `references/options.md` — configuration variable + runtime-override reference table.
- `references/linting-strategy.md` — `lint` vs `mdlint` rationale and snippets.
- `references/error-handling.md` — graceful degradation rules and error text.
- `references/examples.md` — before/after, when to use vs not, customization notes.
