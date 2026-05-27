# Project Board Sync — narrative + rationale

> **Canonical executable snippet lives in `SKILL.md` Step 7.** This file is
> the narrative companion — rationale, edge cases, and pointers — not a
> source of code. If you find yourself copying bash out of here into the
> skill, you've found a regression of issue #747.

After the PR is created, sync cards on the kanban so reviewers see the PR and
the linked Issues are at the right column without a manual drag. Two cards
need to move:

- The new **PR card** → `In review`.
- Each linked **Issue card** (anything matched by `Closes #N` in the PR
  body) → `In progress`, correcting the GitHub builtin's mis-move to
  `In review`.

## Hook auto-skip (issue #390)

If a PostToolUse hook is going to do this work, the skill must NOT run the
inline sync — triple-syncing (skill + hook + GitHub builtin) wastes tokens
and widens the race window. The skill detects the hook by file presence
across three paths:

1. `${REPO_ROOT}/.claude/hooks/post-pr-create-status.sh` —
   AgentToolbox-style in-repo hook.
2. `$HOME/.claude/hooks/post-gh-pr-create.sh` — runtime copy.
3. `$HOME/dotfiles/claude/hooks/post-gh-pr-create.sh` — dotfiles SSOT.

When **any** path exists, the inline snippet is skipped and the hook (or
AgentToolbox hook) handles it. When none exist, the inline snippet runs
as a fallback, preserving behavior for environments without hook support.
Idempotence of `_gh_project_status_sync` (verify pair, issue #393) absorbs
the case where both a dotfiles hook and an AgentToolbox hook fire.

## Why "In review" with no guard (PR card)

The PR lifecycle is linear. `In review` is the canonical resting state from
the moment a PR opens through approval, so unconditional sync is safe — there
is no prior status that should block the move.

## Why "In progress" for linked Issues (not "In review")

The GitHub builtin "Pull request linked to issue" (project workflow #3) moves
Issue cards to "In review" when a PR is opened with `Closes #N`. However, the
intended Issue lifecycle is `Backlog → In progress → Done` — Issues must never
visit "In review" or "Approved" (issue #289).

Calling `_gh_project_status_sync issue … "In progress"` immediately after the
PR is created corrects the builtin's transition. The
`--only-from "Backlog,Ready,In review"` guard explicitly includes `In review`
so we can undo the builtin's mis-move even when it fires before our sync, while
still refusing to drag `Done` Issues backwards if a closed PR is re-opened (#309).

## `GH_REPO` requirement

The closing-issues helper (`_gh_pr_closing_issue_numbers`) needs the repo
slug as `owner/repo` (e.g. `dEitY719/dotfiles`). If `GH_REPO` is unset at
the point Step 7 runs, resolve it via
`gh repo view --json nameWithOwner --jq .nameWithOwner`. This is a thin
wrapper — no auth state changes, no API mutation.

## Behavior summary

- **No projectV2 board attached** — the helper auto-detects zero project items
  and silently returns 0. Nothing happens, no error.
- **PR body has no `Closes #N`** — `_gh_pr_closing_issue_numbers` returns
  nothing; the for-loop body never runs. PR sync still proceeds.
- **Opt-out per invocation** — set `GH_PROJECT_STATUS_SYNC=0` in the
  environment to skip both syncs entirely.
- **Helper unavailable** — when `_HELPER` is unreadable, the inline block
  silently skips (NF-1 fallback, #644). When the file sources but the
  function is undefined (interactive-guard regression, partial sourcing,
  future rename), an explicit `#724` warning is printed and the sync is
  skipped — preventing the silent `rc 127` swallow.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared between `gh:pr`,
`gh:pr-reply`, and other PR/issue lifecycle skills. The skill **sources**
this file; do not duplicate the helper's implementation. The bash that
*calls* the helper, however, is intentionally inlined in `SKILL.md`
Step 7 (issue #747) so the model reads it linearly during execution
without a reference-load indirection.
