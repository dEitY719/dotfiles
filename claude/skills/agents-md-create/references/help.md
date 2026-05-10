# skill:agents-md-create — Help

## Synopsis

```
/agents-md:create [path]
```

## Description

Create a new `AGENTS.md` documentation system for a project from scratch.
Generates a root `AGENTS.md` and nested files as needed, sized by project
classification (small / medium / large). Distinct from `skill:agents-md-refactor`
(existing file) and `skill:agents-md-check` (audit only).

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `path` | Target directory to write `AGENTS.md` into. | Current working directory |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/agents-md:create
/agents-md:create ./packages/api
/agents-md:create -h
```

## Stop conditions

- An `AGENTS.md` already exists at the target — recommend `skill:agents-md-refactor` instead.
- Project type cannot be classified — ask the user for clarification before writing.
