#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_merge_train_close_impl_tab.sh
# Source-of-truth mirror for the step-7 impl-tab close documented in
# claude/skills/gh-pr-merge-train/references/train-loop.md (issue #1565).
#
# The train itself runs inside a Claude session, but this step is a small bash
# block: given the merged PR's head branch, does it find the local worktree,
# match the herdr agent parked on that cwd, and close its tab only when that
# agent is idle?
#
# Keep this file in sync with the bash block in that reference doc. If the doc
# block changes, mirror the change here so the bats suite catches drift.
#
# Test seams: `git`, `herdr`, and `jq` are resolved through the shell's normal
# command lookup, so the bats suite shadows them with functions. Nothing is
# stubbed inside the fixture — the block below is meant to read as the doc
# block does.

# Mirrors the block in
# claude/skills/gh-pr-merge-train/references/train-loop.md → "Closing the
# merged PR's implementation tab", which SKILL.md Step 4 delegates to. Any
# change here must propagate to that block, and vice versa.
#
# Usage: gh_pr_merge_train_close_impl_tab "$HEAD_REF"
#   $1 — the merged PR's headRefName, already in $STATE from the loop's step 1.
#
# Always returns 0: this runs after the merge already succeeded, so it can
# never fail the PR it just merged. It is the belt-and-braces half of #1565 —
# gh:pr-merge Step 5's dispatch closes the same tab first, and finding nothing
# to close is the expected outcome when that worked.
gh_pr_merge_train_close_impl_tab() {
    local _branch="$1"

    # Idle-only, exactly the judgement gh:pr-merge's Step 4 herdr hint already
    # makes: a `working` or `blocked` agent is a live session, and closing its
    # tab kills work in flight. Every gate below is a silent skip.
    command -v herdr >/dev/null 2>&1 || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # Locate the local worktree checked out on the merged branch. substr()
    # rather than $2 so a worktree path containing spaces still resolves; an
    # empty branch matches nothing, so that case falls out of this same gate.
    local _wt_path
    _wt_path=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/${_branch}" \
        '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) {print p; exit}}')
    [ -n "$_wt_path" ] || return 0

    local _agent_json
    _agent_json=$(herdr agent list 2>/dev/null) || return 0

    # `first`: two agents on one cwd is abnormal — take the first, ignore the
    # rest, warn about nothing (same rule as the Step 4 hint). The idle gate
    # stays inside jq, so a tab id exists only for a closable tab — nothing has
    # to carry a status back out through a delimiter.
    local _tab_id
    _tab_id=$(printf '%s' "$_agent_json" | jq -r --arg cwd "$_wt_path" \
        '[.result.agents[]? | select(.cwd == $cwd)] | first
         | select(.agent_status == "idle") | .tab_id // empty' 2>/dev/null)

    [ -n "$_tab_id" ] || return 0

    if herdr tab close "$_tab_id" >/dev/null 2>&1; then
        printf '[INFO] gh:pr-merge-train: closed implementation tab %s (%s).\n' \
            "$_tab_id" "$_wt_path"
    else
        printf '[WARN] gh:pr-merge-train: herdr tab close %s failed — continuing.\n' \
            "$_tab_id"
    fi

    return 0
}
