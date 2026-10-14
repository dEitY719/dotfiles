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
| `per-file` | every staged file; the adapter filters further | shebang, shellcheck, gh_api_type, init_auto_sourcing, custom_tools_entrypoint, direct_exec_guard, hardcoded_home_path, emoji, settings_model_key, interactive_guard, posix_bashism |
| `per-shell-file` | staged `shell-common/functions/*.sh` and `shell-common/tools/integrations/*.sh` that exist (except `*NAMING_CONVENTION*`; `is_shell_lib_file` in `shared.sh`) | naming, ux_usage, help_integrity, subshell_sourcing, pipe_loop, zsh_emulation, alias_conflict, alias_location, wrapper, auto_execution, library_purity |
| `global` | once, with an empty file; staged lists are in `STAGED_FILES` / `STAGED_FILES_WITH_DELETIONS` | backup_files, command_docs_staleness, leak_pattern |

## Whole-file mode (golden rules, #2149)

`git/hooks/checks/run_all.sh <file>...` loads the same modules and runs every
`per-file` / `per-shell-file` check on the given files with `CHECK_MODE=all`
exported; `global` checks are skipped (they judge the staged set). A check
that reads the staged diff must judge the whole file when `CHECK_MODE=all`
(`hardcoded_home_path` does). Every finding, warning or blocking, is a
`<check_name>:<path>` key; keys in `checks/baseline.txt` are legacy
violations and pass, any other key exits 1, and so does a baseline key for a
judged file that no longer reproduces, or whose file is gone (stale). Severity
does not matter here: a `warning` that only informs at commit time fails
golden rules when it is new. A check whose tree still has baselined findings
must be `warning`, since pre-commit has no baseline and a `blocking` one would
reject every commit touching such a file. `tests/golden_rules/test_golden_rules.sh`
runs it over `git ls-files` and holds no rule of its own: a rule lives only in
its check file.

## Order

Reports print blocking checks, then warnings, each in `CHECK_ORDER`
(`git/config/hook-config.sh`) order first and file-name order after.
