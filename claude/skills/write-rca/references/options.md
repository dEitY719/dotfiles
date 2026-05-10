# CLI options and env vars

## Flag matrix

| Option                  | Description                                                                 | Default     |
|-------------------------|-----------------------------------------------------------------------------|-------------|
| `--commit`              | Run `git -C "$RCA_REPO_PATH" add && commit` after Step 4 succeeds.          | off         |
| `--audience <name>`     | One of `blog`, `private`, `internal`. Applies preset in Step 4.             | (all four)  |
| `--private`             | Shortcut for `--audience private`. Strips secrets, sets postmortem-only.    | off         |
| `-h`, `--help`, `help`  | Print `references/help.md` verbatim and stop.                               | —           |

Flags are independent unless noted. `--private` and `--audience private` are
equivalent; if both are given, `--private` wins (lowest-noise form).

## Environment variables (SSOT)

| Variable             | Purpose                                                  | Default                              |
|----------------------|----------------------------------------------------------|--------------------------------------|
| `RCA_REPO_PATH`      | Repository root. SSOT for all output paths in the skill. | `~/para/archive/rca-knowledge`       |
| `RCA_AUTO_COMMIT`    | If `true`, `--commit` is implied for every invocation.   | `false`                              |
| `RCA_AUTO_PUBLISH`   | If `true`, Step 5 also runs `git push` after commit.     | `false`                              |
| `RCA_FORMAT`         | Document format. Only `hybrid-jekyll` is supported.      | `hybrid-jekyll`                      |

### SSOT note

`$RCA_REPO_PATH` is the single source of truth for the repository location.
Older drafts of this skill hardcoded `~/para/archive/rca-knowledge` in
multiple places and at one point referenced `~/para/project/rca-knowledge`
(typo). Both are replaced by `${RCA_REPO_PATH:-~/para/archive/rca-knowledge}`
throughout the skill.

To override, add to your shell profile:

```bash
export RCA_REPO_PATH="$HOME/para/archive/rca-knowledge"
export RCA_AUTO_COMMIT=false
export RCA_AUTO_PUBLISH=false
export RCA_FORMAT="hybrid-jekyll"
```

## Stop conditions related to options

- `--commit` set but `$RCA_REPO_PATH` is not a git working tree → Step 5
  `[FAIL]`.
- `--audience` value not in `{blog, private, internal}` → Step 4 `[FAIL]`.
- `RCA_FORMAT` set to anything other than `hybrid-jekyll` → Step 2 `[FAIL]`
  (no other format is implemented).
