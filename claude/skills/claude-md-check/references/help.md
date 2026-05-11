# claude-md-check — Help

## Usage

```
/claude-md-check [path]
```

Audit a CLAUDE.md orchestrator file against six framework design checks.
Read-only — does not modify the target file.

## Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `path`   | Path to CLAUDE.md to audit | search from cwd |

If `path` names an AGENTS.md, the skill stops and points to `agents-md:check`
instead.

## Output

A table with PASS/WARN/FAIL per check, followed by Issues & Improvements
(WARN/FAIL only) and a Summary line. The Summary always ends with a
`Next:` hint pointing at the next concrete action.

## Examples

```
/claude-md-check                       # search from cwd
/claude-md-check ./CLAUDE.md           # explicit path
/claude-md-check ../other/CLAUDE.md    # outside cwd
```

## Sibling skills

- `agents-md:check` — for AGENTS.md project context files
- `claude-md-create` — bootstrap a new CLAUDE.md
