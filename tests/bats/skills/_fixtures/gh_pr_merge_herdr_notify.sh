#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_merge_herdr_notify.sh
# Source-of-truth mirror for the Step 4 herdr idle-tab hint documented in
# claude/skills/gh-pr-merge/references/herdr-tab-notify.sh.md (issue #1508).
#
# The skill itself runs inside a Claude session, but the hint logic is a
# small bash block that can be tested in isolation: given a branch name,
# does it find a local worktree, match an agent parked on that cwd, and
# print exactly one [INFO] line when that agent is idle?
#
# Keep this file in sync with the bash block in that reference doc. If the
# doc block changes, mirror the change here so the bats suite catches drift.
#
# Test seams: `git`, `herdr`, and `jq` are resolved through the shell's
# normal command lookup, so the bats suite shadows them with functions.
# Nothing here is stubbed inside the fixture — the block below is meant to
# read as the doc block does.

# Mirrors the block in
# claude/skills/gh-pr-merge/references/herdr-tab-notify.sh.md, which
# SKILL.md Step 4 delegates to. Any change here must propagate to that
# block, and vice versa.
#
# Usage: gh_pr_merge_herdr_notify "$HEAD_REF"
#   $1 — the merged PR's headRefName, carried forward from Step 2's
#        already-fetched `gh pr view --json ...,headRefName,...`.
#
# Always returns 0 (NF-1): this is post-merge housekeeping and must never
# fail, block, or alter the merge report. Read-only (NF-2): only `list`
# enumerations are invoked, never a state-changing herdr/git command.
gh_pr_merge_herdr_notify() {
    local _branch="$1"

    # NF-1: every gate here is a silent skip. Either tool missing (the
    # expected state on any machine without the agent runner), or no worktree
    # (the merge ran on a different machine) → the merge report is unaffected.
    # The two builtin `command -v` gates come first so that common case never
    # pays for the worktree scan below.
    command -v herdr >/dev/null 2>&1 || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # "Which herdr agent is sitting on this worktree?" comes from one SSOT
    # (#1569), sourced — never re-implemented here. Mirroring the predicate in
    # this fixture would reintroduce exactly the duplication that let four call
    # sites drift into three different answers, and this hint carried the
    # weakest of them (`.cwd == $wt`, plain string equality). An unreadable
    # helper is a silent skip like every other gate.
    local _lookup_lib="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/herdr_agent_lookup.sh"
    [ -r "$_lookup_lib" ] || return 0
    # shellcheck source=/dev/null
    . "$_lookup_lib" || return 0

    # F-1: locate the local worktree checked out on the merged branch.
    # substr() rather than $2 so a worktree path containing spaces still
    # resolves; --porcelain guarantees the "worktree <path>" / "branch <ref>"
    # line pairing this relies on. An empty branch matches nothing, so the
    # empty-HEAD_REF case falls out of this same gate.
    local _wt_path
    _wt_path=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/${_branch}" \
        '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) print p}' | head -1)

    # F-2: read-only agent enumeration. The lookup matches BOTH `cwd` (where the
    # pane was opened) and `foreground_cwd` (where its shell stands now), on a
    # path BOUNDARY, against the PHYSICAL path — and it takes the first match,
    # because two agents on one worktree is abnormal: ignore the rest, warn
    # about nothing.
    #
    # F-4: the `idle` argument puts the status gate inside the lookup, so a
    # `working`/`blocked` agent yields nothing at all and does not even pay for
    # the workspace lookup below. A non-zero return is either "herdr could not
    # be asked" or "nothing idle is there"; this hint treats both the same.
    local _match
    [ -n "$_wt_path" ] || return 0
    _match=$(herdr_agent_match_for_cwd "$(herdr_agent_physical_path "$_wt_path")" idle) || return 0

    # tab_id <TAB> agent_status <TAB> workspace_id. The middle field is
    # discarded: the filter above already pinned it to `idle`.
    local _tab_id _ws_id _ws_label
    IFS=$'\t' read -r _tab_id _ _ws_id <<<"$_match"

    # Label is cosmetic — fall back to the raw workspace id when the second
    # read-only lookup fails or the workspace is unlabeled.
    _ws_label=$(herdr workspace list 2>/dev/null | jq -r --arg id "$_ws_id" \
        '.result.workspaces[]? | select(.workspace_id == $id) | .label // empty' 2>/dev/null | head -1)

    # F-3: exactly one line, only for an idle agent. The path printed is the one
    # `git worktree list` reported, not its resolved twin — that is the spelling
    # the human will recognise.
    printf "[INFO] herdr tab %s/%s is idle for the merged branch's worktree (%s) — consider: herdr tab close %s / ai-worktree:teardown\n" \
        "${_ws_label:-$_ws_id}" "$_tab_id" "$_wt_path" "$_tab_id"

    return 0
}
