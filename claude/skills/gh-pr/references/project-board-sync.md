# Project Board Sync — push the new PR's card to "In review" + linked Issues to "In progress"

After the PR is created, sync cards on the kanban so reviewers see the PR and
the linked Issues are at the right column without a manual drag.

## Hook auto-skip (issue #390)

If a PostToolUse hook is going to do this work, the skill must NOT run the
inline sync — triple-syncing (skill + hook + GitHub builtin) wastes tokens
and widens the race window. Detect the hook by file presence and skip:

```bash
hook_skip=0
for hook_path in \
    "${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}/.claude/hooks/post-pr-create-status.sh" \
    "$HOME/.claude/hooks/post-gh-pr-create.sh" \
    "$HOME/dotfiles/claude/hooks/post-gh-pr-create.sh"
do
    if [ -x "$hook_path" ]; then
        hook_skip=1
        printf '[gh-pr] board sync delegated to PostToolUse hook (%s) — skipping inline.\n' "$hook_path" >&2
        break
    fi
done

if [ "$hook_skip" -eq 0 ]; then
    # Run the snippet below.
    :
fi
```

The three paths cover (a) AgentToolbox-style in-repo hook, (b) a runtime
copy at `~/.claude/hooks/`, and (c) the dotfiles SSOT location. When **any**
exists, the inline snippet is skipped — the hook (or the AgentToolbox hook)
will handle it. When none exist, the inline snippet runs as a fallback,
preserving behavior for environments without hook support. Idempotence of
`_gh_project_status_sync` (verify pair, issue #393) absorbs the case where
both a dotfiles hook and an AgentToolbox hook fire.

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

## Snippet

Source the shared helper, then call it with the new PR number:

```bash
# helper-fallback NF-1 (#644): silent-skip when helper missing.
# Defense-in-depth (#724): also detect "[ -r ] passes but function never
# defined" (interactive-guard regression, partial sourcing, future rename).
# `|| true` would otherwise absorb `command not found` (rc 127) and the
# entire reconciliation would silently no-op — the failure mode from #724.
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
if [ -r "$_HELPER" ]; then
    . "$_HELPER"
    if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
        printf '[gh-pr] %s sourced but _gh_project_status_sync undefined — board sync skipped (#724).\n' \
            "$_HELPER" >&2
    else
        _gh_project_status_sync pr "$PR_NUMBER" "In review" || true
        for _issue in $(_gh_pr_closing_issue_numbers "$PR_NUMBER" "$GH_REPO" 2>/dev/null || true); do
            _gh_project_status_sync issue "$_issue" "In progress" \
                --only-from "Backlog,Ready,In review" || true
        done
    fi
fi
```

`GH_REPO` must be `owner/repo` (e.g. `dEitY719/dotfiles`). If unavailable,
resolve it via `gh repo view --json nameWithOwner --jq .nameWithOwner`.

## Behavior

- **No projectV2 board attached** — the helper auto-detects zero project items
  and silently returns 0. Nothing happens, no error.
- **PR body has no `Closes #N`** — `_gh_pr_closing_issue_numbers` returns
  nothing; the for-loop body never runs. PR sync still proceeds.
- **Opt-out per invocation** — set `GH_PROJECT_STATUS_SYNC=0` in the
  environment to skip both syncs entirely.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared between `gh:pr`,
`gh:pr-reply`, and other PR/issue lifecycle skills. Do not inline-copy the
snippet; always source the file so a single fix propagates everywhere.
