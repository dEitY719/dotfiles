# gh:pr — Accepted Options

| Argument | Description | Default |
|----------|-------------|---------|
| `[N]` (positional) | Legacy `/gh:pr 123` form — overrides issue auto-detection. | — |
| `--no-stack` | Force a non-stacked PR even when stacked-PR signals fire. | off |
| `--base <branch>` | Explicit base branch; bypasses stacked-PR detection. | repo default |
| `GH_DISABLE_AI_METRICS=1` (env) | Skip ai-metrics footer append in Step 4. | off |
| `GH_PR_LINT_BYPASS=1` (env) | Skip Step 4.5 lint guard. | off |
| `DOTFILES_ROOT` (env) | Root used to source `gh_pr_lint.sh`. | `$HOME/dotfiles` |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |

`--no-stack` and `--base` are mutually exclusive — see Step 1a exit codes.
Auto-detected parent PR must be `OPEN` — refuses (rc=5) otherwise.
