# devx:ai-context — Help

## Synopsis

```
/devx:ai-context [action] [path]
/devx:ai-context [action] [--file PATH] [--kind KIND]
/devx:ai-context -h | --help | help
```

## Description

Single entry point for AI context-injection files (`CLAUDE.md`, `AGENTS.md`,
`GEMINI.md`). Replaces five legacy skills:

- `agents-md:check`
- `agents-md:create`
- `agents-md:refactor`
- `claude-md-check`
- `claude-md-create`

The legacy skills have been deleted (follow-up to #539, see issue #560).

## Actions

| Action     | Behavior                                                     |
|------------|--------------------------------------------------------------|
| `check`    | (default) Audit the target file; never mutate                |
| `create`   | Generate a new context file from a template (with confirmation) |
| `refactor` | Slim and split an existing file (with confirmation)          |
| `help`     | Print this page and stop                                     |

## Arguments

| Arg            | Description                                       | Default       |
|----------------|---------------------------------------------------|---------------|
| `action`       | `check` / `create` / `refactor` / `help`          | `check`       |
| `path`         | Explicit target file path                         | auto-detect   |
| `--file PATH`  | Same as positional `path`; takes precedence       | —             |
| `--kind KIND`  | Force adapter: `agents` / `claude` / `gemini`     | from filename |
| `-h`/`--help`  | Print this help and stop                          | —             |

Auto-detection priority in cwd: `CLAUDE.md` → `AGENTS.md` → `GEMINI.md`.

## Examples

```
/devx:ai-context                               # check the auto-detected file
/devx:ai-context check ./docs/AGENTS.md        # check a specific path
/devx:ai-context check --file ./CLAUDE.md      # equivalent
/devx:ai-context create --kind agents          # walk through new-AGENTS.md flow
/devx:ai-context create --kind claude          # walk through new-CLAUDE.md flow
/devx:ai-context refactor                      # plan + execute split on confirm
/devx:ai-context help                          # this page
```

## Stop conditions

- No context file found and action is `check`/`refactor` → suggest `create`.
- Multiple files found and action is `create`/`refactor` → prompt; never auto-overwrite.
- Target is unreadable → abort with the underlying error.
- Target is `SKILL.md` → route to `skill:check`.
- Target is `*.sh` → route to `sh:check`.

## Migration from legacy skills

| Legacy command                 | New command                                |
|--------------------------------|--------------------------------------------|
| `/agents-md:check [path]`      | `/devx:ai-context check [path]`            |
| `/agents-md:create`            | `/devx:ai-context create --kind agents`    |
| `/agents-md:refactor`          | `/devx:ai-context refactor --kind agents`  |
| `/claude-md-check [path]`      | `/devx:ai-context check [path]`            |
| `/claude-md-create`            | `/devx:ai-context create --kind claude`    |

Legacy skill directories have been removed (issue #560) — use the commands above.

## Output

See `references/report-template.md` for the canonical report layout.
Verdict is `[OK]` if no check fails, else `[FAIL]`. Always ends with a
`Next:` action hint.
