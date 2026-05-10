# skill:claude-md-create — Help

## Synopsis

```
/claude-md-create [path]
```

## Description

Create a `CLAUDE.md` orchestrator file for an AI agent framework from scratch.
Defines roles, commands, permissions, and delegation patterns sized by
framework scale (simple / standard / large). Distinct from `skill:claude-md-check`
(audit only).

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `path` | Target directory to write `CLAUDE.md` into. | Current working directory |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/claude-md-create
/claude-md-create ./my-agent-framework
/claude-md-create -h
```

## Stop conditions

- A `CLAUDE.md` already exists at the target — confirm overwrite before proceeding.
- Discover phase (Phase 0) cannot extract domain / agent list — ask the user before writing.
