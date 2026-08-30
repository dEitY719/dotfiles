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

    # "Which herdr agent is sitting on this worktree?" comes from one SSOT
    # (#1569), sourced — never re-implemented here. Mirroring the predicate in
    # this fixture would reintroduce exactly the duplication that let four call
    # sites drift into three different answers. A missing helper skips the
    # close, silently, like every other gate here.
    local _lookup_lib="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/herdr_agent_lookup.sh"
    [ -r "$_lookup_lib" ] || return 0
    # shellcheck source=/dev/null
    . "$_lookup_lib" || return 0

    # Locate the local worktree checked out on the merged branch. substr()
    # rather than $2 so a worktree path containing spaces still resolves; an
    # empty branch matches nothing, so that case falls out of this same gate.
    local _wt_path
    _wt_path=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/${_branch}" \
        '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) {print p; exit}}')

    # `herdr_agent_physical_path` resolves symlinks before comparing: `git
    # worktree list` reports the path as it was created, herdr reports where the
    # pane actually stands, and a single symlinked component makes those two
    # strings differ. `herdr_agent_tab_for_cwd` then matches BOTH `cwd` (where
    # the pane was opened) and `foreground_cwd` (where its shell stands now), on
    # a path BOUNDARY, so an agent that `cd`-ed one level inside the worktree is
    # still found while `/work/repo-11` never matches `/work/repo-1`. Two agents
    # on one worktree is abnormal — the helper takes the first, ignores the
    # rest, and warns about nothing (same rule as the Step 4 hint).
    #
    # The `idle` argument keeps the status gate inside the lookup, so a tab id
    # comes back only for a closable tab and nothing has to carry a status out
    # through a delimiter. It judges that first match rather than hunting for an
    # idle one among several. A non-zero return is either "herdr could not be
    # asked" or "nothing closable is there" — both are a silent skip here.
    local _tab_id
    if [ -n "$_wt_path" ] &&
        _tab_id=$(herdr_agent_tab_for_cwd "$(herdr_agent_physical_path "$_wt_path")" idle); then
        if herdr tab close "$_tab_id" >/dev/null 2>&1; then
            printf '[INFO] gh:pr-merge-train: closed implementation tab %s (%s).\n' \
                "$_tab_id" "$_wt_path"
        else
            printf '[WARN] gh:pr-merge-train: herdr tab close %s failed — continuing.\n' \
                "$_tab_id"
        fi
    fi

    return 0
}
