# Board Status Policy — `Approved` column gate

This is the single-source-of-truth for what the `Approved` column on a
projectV2 board means in this org's workflow, and which guard rails
enforce it.

## Rule

A PR card may only sit in the `Approved` column when GitHub's
`reviewDecision` for that PR equals `APPROVED`. Any other state
(`REVIEW_REQUIRED`, `CHANGES_REQUESTED`, empty) is a policy violation.

The same rule cascades into `gh:pr-merge`: a card whose Status is not
`Approved` cannot be merged via the regular `/gh-pr-merge` skill — the
caller is redirected to `/gh-pr-merge-emergency` for an admin override
with audit trail.

## Why fail-closed instead of advisory

`reviewDecision == APPROVED` is necessary but not sufficient on this
board:

- Solo / personal repos lack branch protection. `reviewDecision` stays
  empty for self-authored PRs, so a CI-only check would pass without any
  human signal at all.
- Teammate review is captured by the board column, not by GitHub's
  reviewer mechanism — the column is what the team eyes when triaging.

A fail-closed guard at both write points (transition + merge) keeps the
column meaningful: when you see a PR in `Approved`, it actually has been
through reviewer eyes.

## Two enforcement points

### 1. Transition into the column (write side)

`shell-common/functions/gh_project_status.sh` rejects any
`_gh_project_status_sync pr <N> "Approved"` call when
`gh pr view --json reviewDecision` returns anything other than
`APPROVED`. Failure mode is `exit 2` with a clear stderr line; bypass is
`_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1` for emergency operator
intent.

This guard was added in #393 along with the verify pair — both are
defenses against the same class of bug (Status drifts away from what the
helper thinks it set).

### 2. Merge gate (read side)

`gh:pr-merge` Step 4-B (added by #397) reads the current board Status
before merging. If Status `!= Approved`, the merge is refused and the
operator is redirected to `gh:pr-merge-emergency`. Escape:
`GH_PR_MERGE_SKIP_BOARD_CHECK=1` for repos in transition or for
single-shot bypass with audit trail.

The two checks are intentionally redundant. If the helper's transition
guard is bypassed, the merge gate still catches it; if the merge gate
is bypassed (env var), the audit issue created by
`gh:pr-merge-emergency` records it.

## Out of scope

- Issue cards never visit `Approved` per `github-project-board.md`;
  guards above only apply when `kind == pr`.
- Repos without a projectV2 attachment are auto-detected and skipped:
  the helper finds zero items and returns 0. No board → no policy →
  legacy CI-only flow (`reviewDecision == APPROVED` still required by
  `gh:pr-merge` Step 2).

## Audit

`gh-audit-builtin-workflows` (shell-common function added in #397)
checks that the asynchronous "Pull request linked to issue" builtin
workflow is OFF on every attached projectV2 — that builtin races with
the deterministic Status transitions and would silently invalidate this
guard.

## See also

- `shell-common/functions/gh_project_status.sh` — write-side guard impl.
- `claude/skills/gh-pr-merge/SKILL.md` Step 4-B — merge-gate impl.
- `claude/skills/gh-pr-merge/references/board-policy.md` — cross-link.
- `docs/standards/github-project-board.md` — column semantics SSOT.
