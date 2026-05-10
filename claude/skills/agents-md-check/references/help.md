# skill:agents-md-check — Help

## Synopsis

```
/agents-md:check [path]
```

## Description

Audit an existing `AGENTS.md` file for compliance with project documentation
standards. Reports pass/fail/warn per criterion with concrete improvement
suggestions. Do NOT use for `CLAUDE.md` orchestrator files — use
`skill:claude-md-check` instead.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `path` | Explicit path to the `AGENTS.md` to audit. | Auto-detect in cwd |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/agents-md:check
/agents-md:check ./docs/AGENTS.md
/agents-md:check -h
```

## Stop conditions

- No `AGENTS.md` found at the resolved path — list candidates and ask which to check.
- Target is a `CLAUDE.md` orchestrator file — redirect to `skill:claude-md-check`.
