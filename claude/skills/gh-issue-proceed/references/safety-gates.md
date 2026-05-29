# gh:issue-proceed — Safety gates

Four layers, strictest to weakest. Each can independently trigger abort.
This file is the SSOT for `ABSOLUTE_BLOCK_PATTERNS` (Layer 1); the bats
fixture `tests/bats/skills/_fixtures/gh_issue_proceed_safety.sh` mirrors
the patterns and the suite `gh_issue_proceed_safety.bats` covers one
positive + one negative per pattern.

## Layer 1 — Absolute prohibitions

Ignored **even if the issue body authorizes them**. A match aborts the
flow, comments `[blocked] absolute prohibition triggered: <pattern>` on
the proceed issue, and leaves the issue open for manual review.

| Key | Detection | Behavior |
|---|---|---|
| `force_push_default` | `git push --force`/`-f` targeting the default branch | abort |
| `force_push_general` | `git push --force`/`-f` (any branch) | abort — only `--force-with-lease` is allowed, and only when §safety authorizes |
| `rm_rf_outside_pwd` | `rm -rf` with a path resolving outside `$PWD` | abort |
| `destructive_db` | `DROP`, `TRUNCATE`, `admin reset`, mass `DELETE` | abort |
| `secret_in_output` | `*_KEY` / `*_TOKEN` / `*_SECRET` / `password=` / `Bearer ` / JWT shape in stdout/stderr | abort + output never posted to GitHub |
| `cross_worktree_mutation` | write path resolves outside the active worktree (`git worktree list`) | abort |
| `gh_pr_merge` | `gh pr merge` | abort — sibling skills own merges |
| `branch_deletion` | `git branch -D`, `gh api -X DELETE` against a branch ref | abort |
| `reopen_foreign_closed` | reopen of an issue closed by someone else | abort |

The secret scanner (`secret_in_output`) is the one monitor that is **never
overrideable** — a leaked credential cannot be un-leaked once posted.

## Layer 2 — Conditional permissions

Allowed **only** when §safety carries the matching `allow:` token (exact
substring). Default-deny: a missing token promotes the action to a Layer-1
abort.

| Action | Required §safety token |
|---|---|
| Bulk-close (≥5 issues) | `allow: bulk-close` |
| Bulk-create (≥5 new issues) | `allow: bulk-create-issue` |
| Force-with-lease push | `allow: force-with-lease` |
| Non-allowlisted outbound network | `allow: net: <host glob>` |
| Cross-repo mutation | `allow: cross-repo: <owner/repo>` |

## Layer 3 — Pre-flight (Step 3 entry, run in parallel)

All must pass or the skill stops with a hint:

- Current branch ≠ default — enforced only for the mutation class
  (`references/preconditions.md`).
- No untracked secret-shaped files (`.env`, `*.pem`, `*.key`) in the tree.
- `gh auth status` succeeds.
- §preconditions block dry-runs successfully (any embedded check commands).

## Layer 4 — Runtime monitors

| Monitor | Default | Override |
|---|---|---|
| Per-step timeout | 5 min | §preconditions may state `per-step timeout: <N>m` |
| Global timeout | 60 min | §preconditions may state `global timeout: <N>m` |
| Output secret scanner | always on | none — never overrideable |
| Write-action quota | per-type ceiling **5** (close / create / commit / pr / comment counted separately, excluding self-comment / self-close) **and** total ceiling **20** | §safety `allow: bulk-close` / `bulk-create-issue` raises the matching per-type ceiling to 50; total stays 20 unless §safety also declares `allow: total-quota: <N>` |
| Edit-path memory | always on | none — needed for the §6 audit |

## Quota counting rules

- Self-comment on the proceed issue and self-close of the proceed issue do
  **not** count against any quota (they are bookkeeping, not side-effects).
- The total ceiling (20) is checked across all types combined; reaching it
  aborts the loop with `[blocked] write-action total quota exceeded`, even
  if no per-type ceiling was hit.
