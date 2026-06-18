# Options — full flag/argument reference for claude-plugin:create

Positional `<plugin-name>` (required) + optional `[skill ...]` list, plus the
flags below. (The same surface, with examples, is in `help.md`.)

| Option | Description | Default |
|--------|-------------|---------|
| `<plugin-name>` | repo name in `claude-plugin-<domain>` form (required) | — |
| `[skill ...]` | skill directory names to copy (space-separated) | inferred from chat, else ask |
| `--src <path>` | skill source directory | `~/dotfiles/claude/skills/` |
| `--dest <path>` | repo creation location | `~/para/project/` |
| `--host <host>` | GitHub host | `github.samsungds.net` |
| `--owner <owner>` | GitHub owner | `byoungwoo-yoon` |
| `--plugin <name>` | plugin key (inner name) | domain part of name |
| `--dry-run` | plan only — no writes/repo/commit | off |
| `-h`/`--help` | print help, stop | — |

## Validation rules (Step 1)

- Prepend `claude-plugin-` if the prefix is missing (tell the user).
- Enforce lowercase-hyphen naming (GitHub repo naming rules).
- Abort if `--src` is missing.
- Abort if `<dest>/<plugin-name>` already exists — no overwrite, NOT idempotent.
- `[skill ...]`: infer from the conversation when omitted; if not inferable,
  ask the user (never guess).

## Golden `mono` layout built in Step 3

```
<dest>/<plugin-name>/
  .claude-plugin/marketplace.json
  plugins/<plugin>/.claude-plugin/plugin.json
  plugins/<plugin>/skills/          # empty — skills copied in at Step 4
  docs/skill-guides/
  docs/skill-output/
  README.md
  LICENSE
  .gitignore
```

May delegate the skeleton dirs to
`claude-plugin:structure-refactor --apply --mandatory`.
