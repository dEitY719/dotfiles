# Board Status Policy — cross-link

The full rule set for the `Approved` column gate lives in
`claude/skills/gh-pr-approve/references/board-policy.md`. This file is
a thin pointer so the merge skill can cite the SSOT without duplicating
its prose.

## TL;DR for `gh:pr-merge` callers

- A PR card must sit in `Approved` to merge via `/gh-pr-merge`.
- Status `!= Approved` → `/gh-pr-merge` exits 2 and points at
  `/gh-pr-merge-emergency` for admin override + audit trail.
- Repos without a projectV2 attachment auto-skip Step 2-B
  (`gh-pr-merge` SKILL.md detects empty Status and continues).
- Bypass for in-transition repos: `GH_PR_MERGE_SKIP_BOARD_CHECK=1`.

## Implementation

Step 2-B of `gh:pr-merge/SKILL.md` runs immediately before Step 3 (the
merge call). It re-uses `_gh_project_status_query_current` from
`shell-common/functions/gh_project_status.sh` so all helpers agree on
which board / which Status is canonical (no inline GraphQL drift).

## See also

- `claude/skills/gh-pr-approve/references/board-policy.md` — full rule
  set, why fail-closed, the dual-write guard rationale.
- `shell-common/functions/gh_project_status.sh` — `Approved` write-side
  guard (the other half of the dual gate).
- `shell-common/functions/gh_audit_builtin_workflows.sh` — audits that
  the "Pull request linked to issue" builtin is OFF, so the guard isn't
  invalidated by an async overwrite.
- `docs/.ssot/github-project-board.md` — column semantics SSOT.
