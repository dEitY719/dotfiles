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

    # F-1: locate the local worktree checked out on the merged branch.
    # substr() rather than $2 so a worktree path containing spaces still
    # resolves; --porcelain guarantees the "worktree <path>" / "branch <ref>"
    # line pairing this relies on. An empty branch matches nothing, so the
    # empty-HEAD_REF case falls out of this same gate.
    local _wt_path
    _wt_path=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/${_branch}" \
        '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) print p}' | head -1)
    [ -n "$_wt_path" ] || return 0

    # F-2: read-only agent enumeration; match on cwd == worktree path.
    local _agent_json
    _agent_json=$(herdr agent list 2>/dev/null) || return 0

    # head -1: two agents on one cwd is abnormal — take the first, ignore
    # the rest, warn about nothing.
    local _match
    _match=$(printf '%s' "$_agent_json" | jq -r --arg cwd "$_wt_path" \
        '.result.agents[]? | select(.cwd == $cwd)
         | "\(.tab_id)\t\(.agent_status)\t\(.workspace_id)"' 2>/dev/null | head -1)
    [ -n "$_match" ] || return 0

    local _tab_id _agent_status _ws_id _ws_label
    IFS=$'\t' read -r _tab_id _agent_status _ws_id <<<"$_match"

    # F-4: working/blocked/anything-but-idle prints nothing at all.
    [ "$_agent_status" = "idle" ] || return 0

    # Label is cosmetic — fall back to the raw workspace id when the second
    # read-only lookup fails or the workspace is unlabeled.
    _ws_label=$(herdr workspace list 2>/dev/null | jq -r --arg id "$_ws_id" \
        '.result.workspaces[]? | select(.workspace_id == $id) | .label' 2>/dev/null | head -1)

    # F-3: exactly one line, only for an idle agent.
    printf "[INFO] herdr tab %s/%s is idle for the merged branch's worktree (%s) — consider: herdr tab close %s / ai-worktree:teardown\n" \
        "${_ws_label:-$_ws_id}" "$_tab_id" "$_wt_path" "$_tab_id"

    return 0
}
