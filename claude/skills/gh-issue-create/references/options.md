# gh:issue-create — Options

| Argument | Description | Default |
|----------|-------------|---------|
| `[remote]` (positional) | Target remote name. Resolved to `TARGET_REPO=<owner>/<repo>`. Fails fast if missing. | `origin` |
| `--no-auto-labels` | Skip Step 2.5 entirely; user `--label` flags remain in effect. | off |
| `--auto-label-debug` | Verbose stderr trace of Stage-1 detection and the kept/dropped label sets. | off |
| `--label <name>` | User label, union with Step 2.5 auto-labels. Repeatable. | — |
| `--assignee @me` | Only added when the user explicitly asks. | off |
| `--as-discussion <category>` | Route to [[gh-discussion-create]] instead of creating an Issue. Category is one of `Ideas` / `Q&A` / `Announcements` / `Lessons` (case-insensitive). Skips Step 2.5 (auto-labels) and Step 4's `gh issue create` — Discussions do not carry labels/milestones. `--label` / `--assignee` flags, if also passed, are ignored with a 1-line warning. | off |
| `GH_DISABLE_AI_METRICS=1` (env) | Skip ai-metrics footer append in Step 4. | off |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |
