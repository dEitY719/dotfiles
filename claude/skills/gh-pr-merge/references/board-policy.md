# Board Status Policy — cross-link

The full rule set for the `Approved` column lives in
`claude/skills/gh-pr-approve/references/board-policy.md`. This file is
a thin pointer so the merge skill can cite the SSOT without duplicating
its prose.

## TL;DR for `gh:pr-merge` callers

- The board Status is **advisory**, not a merge gate. `/gh-pr-merge`
  never reads it and never refuses on it.
- Approval enforcement is the `reviewDecision` hard stop in Step 2 only
  (`references/strategy-selection.md` → "Branch protection detection").
- `gh:pr-approve` still owns the write side: a human running
  `/gh-pr-approve` is what moves a card into `Approved`.

## Retired: Step 2-B (removed in #1513)

Step 2-B used to read the current board Status via
`_gh_project_status_query_current` and exit 2 unless it was `Approved`
(escape: `GH_PR_MERGE_SKIP_BOARD_CHECK=1`). Both the step and the env
var are gone.

Why: `dEitY719/dotfiles` has no branch protection and every PR is
self-authored, and GitHub forbids approving your own PR. `agy` / `codex`
reviews post as `COMMENTED`, so `reviewDecision` never changes and the
builtin `Code review approved` workflow never fires — leaving no path,
manual or automated, to move a card into `Approved`. The gate was
therefore permanently un-satisfiable here and blocked every merge. A
protection-absent exception would have been equivalent to permanent
disablement (this repo never has protection), so the gate was deleted
outright and documented instead.

## See also

- `claude/skills/gh-pr-approve/references/board-policy.md` — full rule
  set, why fail-closed, the write-side guard rationale.
- `shell-common/functions/gh_project_status.sh` — `Approved` write-side
  guard (unchanged by #1513).
- `shell-common/functions/gh_audit_builtin_workflows.sh` — audits that
  the "Pull request linked to issue" builtin is OFF, so the guard isn't
  invalidated by an async overwrite.
- `docs/.ssot/github-project-board.md` — column semantics SSOT.
