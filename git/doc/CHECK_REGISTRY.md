# Pre-commit check registry (#2143)

`git/hooks/pre-commit` sources every `git/hooks/checks/*_check.sh` and registers the
check it declares. Adding a check means adding one file; the runner is never
edited. `shared.sh` and `main_branch_guard.sh` are libraries the runner loads
explicitly; a `*_check.sh` that sets no `CHECK_NAME` (for example
`closing_keyword_check.sh`, used by `commit-msg`) is loaded but not registered.

## Contract

Each check file keeps its own judgment functions and ends with an adapter:

| Name | Required | Meaning |
|---|---|---|
| `CHECK_NAME` | yes | Unique identifier, `[a-z][a-z0-9_]*` |
| `CHECK_SCOPE` | yes | `per-file`, `per-shell-file` or `global` (below) |
| `CHECK_SEVERITY` | yes | `blocking` (fails the commit) or `warning` |
| `CHECK_TITLE` | yes | Report heading |
| `CHECK_LABEL` | no | Warning tag instead of `WARNING` (`INFO`, `CLEANUP`) |
| `CHECK_REPORT_LINES` | no | Show only the first N report lines (default: all) |
| `CHECK_HINT` | no | Lines printed under the report |
| `CHECK_COUNT_LINES` | no | `1`: count each report line as a finding (default: one per failing `check_run` call) |
| `check_run <repo_root> <tmpdir> <file-or-empty> <out>` | yes | Append findings to `<out>`; return 1 on a finding, 0 otherwise |

`<file>` is a repo-relative staged path (ACMR). `<tmpdir>` is a per-run
scratch dir the runner deletes on exit. A missing or invalid declaration
blocks the commit, so a broken check never turns itself off silently.

## Scopes

| Scope | Called with | Checks |
|---|---|---|
| `per-file` | every staged file; the adapter filters further | shebang, shellcheck, gh_api_type, init_auto_sourcing, custom_tools_entrypoint, direct_exec_guard, hardcoded_home_path |
| `per-shell-file` | staged `shell-common/functions/*.sh` and `shell-common/tools/integrations/*.sh` that exist (except `*NAMING_CONVENTION*`) | naming, ux_usage, help_integrity, subshell_sourcing, pipe_loop, zsh_emulation, alias_conflict, alias_location, wrapper, auto_execution, library_purity |
| `global` | once, with an empty file; staged lists are in `STAGED_FILES` / `STAGED_FILES_WITH_DELETIONS` | backup_files, command_docs_staleness, leak_pattern |

## Order and rollback

Reports print blocking checks, then warnings, each in `CHECK_ORDER`
(`git/config/hook-config.sh`) order first and file-name order after.
`GIT_HOOKS_LEGACY_DISPATCH=1` runs `git/hooks/pre-commit.legacy`, the old
explicit dispatch, for one release.
