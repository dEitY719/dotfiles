#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_resolve_outdated.sh
# gh:pr-resolve-outdated Step 5's `review-passed` reconciliation (issue #1698).
#
# Before this file existed, Step 5 unconditionally dropped `review-passed`
# after every successful `git push --force-with-lease` — the rebase changed
# `head_sha`, and the label is a claim about one specific `head_sha` (SSOT
# #1563). That is correct when the rebase actually changed reviewed content,
# but a clean, conflict-free rebase onto a moved base often reproduces the
# EXACT SAME diff under a new commit SHA. Dropping the label there forces a
# full `devx:pr-review-all` re-run (4 external CLIs) for zero new content —
# observed 2026-09-01: 4 PRs stuck on this after a `gh:pr-merge-train` run.
#
# Fix: compare `git patch-id --stable` of the PR's diff before vs. after the
# rebase. Identical, AND `review-passed` is CURRENTLY on the PR -> the label
# is still true for the new head, so instead of dropping it, re-post the SAME
# freshness marker format (#1601) for the new SHA — the existing
# `_gh_pr_merge_train_review_passed_stale()` reader then sees it as fresh on
# the very next tick, with no changes to that reader or to the marker format.
# Anything else (patch-id differs, unreadable, or the label was never there to
# begin with) -> drop as before (a no-op when absent). Conflict resolution
# (`gh:pr-resolve-conflict`) is untouched by this file and keeps its own
# unconditional drop, since resolving a conflict by definition changes content.
#
# The label add + marker post below are done directly (`_gh_pr_edit_safe_label`
# + one `gh api` POST in the exact format `devx_pr_review_all_write_label`
# already uses), NOT by calling `devx_pr_review_all_write_label` itself — that
# helper's first action is deleting the OPPOSITE label (`review-blocked`,
# because it services both directions), which would violate this skill's
# absolute "never touch review-blocked" constraint (PR #1699 review, codex
# BLOCKER). Checking current-label presence first also closes a second gap
# from the same review: without it, a PR that was NEVER reviewed could earn
# `review-passed` from a coincidentally-matching patch-id — a self-certifying
# grant this file must never manufacture.
#
# Usage:
#   _gh_pr_resolve_outdated_patch_id <base-sha> <head-sha> [worktree-path]
#   _gh_pr_resolve_outdated_has_label <pr> <repo> <host> <label>
#   _gh_pr_resolve_outdated_reconcile_review_passed \
#       <pr> <repo> <host> <old-base-sha> <old-head-sha> \
#       <new-base-sha> <new-head-sha> [worktree-path]
#   (the freshness marker, when reposted, is stamped with <new-head-sha>)

# One patch-id hash for a whole diff range (not per-commit): `git patch-id
# --stable` accepts a multi-commit diff on stdin and folds it into one hash,
# which is exactly the whole-PR-range comparison this needs. Empty output
# (no line at all — an empty diff, or `git diff`/`git patch-id` itself
# failing) is reported as an empty string, never guessed at: the caller
# treats "unreadable" the same as "different" (fail closed, same rule this
# repo already uses for the approval gate and the #1601 freshness check).
_gh_pr_resolve_outdated_patch_id() {
    local _base="$1" _head="$2" _worktree="${3-}"
    if [ -z "$_base" ] || [ -z "$_head" ]; then
        printf '[gh-pr-resolve-outdated] usage: _gh_pr_resolve_outdated_patch_id <base-sha> <head-sha> [worktree-path]\n' >&2
        return 2
    fi
    local _out
    if [ -n "$_worktree" ]; then
        _out=$(git -C "$_worktree" diff "$_base".."$_head" 2>/dev/null | git -C "$_worktree" patch-id --stable 2>/dev/null)
    else
        _out=$(git diff "$_base".."$_head" 2>/dev/null | git patch-id --stable 2>/dev/null)
    fi
    # patch-id output is "<hash> <commit>"; only the hash is comparable across
    # the two sides (the trailing commit field differs by construction).
    printf '%s\n' "$_out" | awk '{print $1; exit}'
}

# Returns 0 when <label> is currently on the PR, 1 when it is not (including
# every lookup failure — fail closed, same as the freshness check this file
# feeds: an unreadable label list must never be read as "present").
_gh_pr_resolve_outdated_has_label() {
    local _pr="$1" _repo="$2" _host="${3-}" _label="$4"
    if [ -z "$_pr" ] || [ -z "$_repo" ] || [ -z "$_label" ]; then
        printf '[gh-pr-resolve-outdated] usage: _gh_pr_resolve_outdated_has_label <pr> <repo> <host> <label>\n' >&2
        return 1
    fi
    local _labels
    _labels=$(
        if [ -n "$_host" ]; then
            # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
            export GH_HOST="$_host"
        fi
        gh api "repos/$_repo/issues/$_pr/labels" --jq '.[].name' 2>/dev/null
    ) || return 1
    printf '%s\n' "$_labels" | grep -Fxq -- "$_label"
}

# Soft-fail throughout (same contract as the unconditional drop it replaces):
# a failed reconciliation costs one stderr line, never the caller's exit
# status — Step 4's push already succeeded, so this step must never turn that
# into a failure.
_gh_pr_resolve_outdated_reconcile_review_passed() {
    local _pr="$1" _repo="$2" _host="$3"
    local _old_base="$4" _old_head="$5" _new_base="$6" _new_head="$7"
    local _worktree="${8-}"

    if [ -z "$_pr" ] || [ -z "$_repo" ]; then
        printf '[gh-pr-resolve-outdated] usage: _gh_pr_resolve_outdated_reconcile_review_passed <pr> <repo> <host> <old-base> <old-head> <new-base> <new-head> [worktree-path]\n' >&2
        return 2
    fi

    if ! command -v _gh_pr_drop_label >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh" 2>/dev/null || :
    fi

    local _old_pid _new_pid
    _old_pid=$(_gh_pr_resolve_outdated_patch_id "$_old_base" "$_old_head" "$_worktree")
    _new_pid=$(_gh_pr_resolve_outdated_patch_id "$_new_base" "$_new_head" "$_worktree")

    if [ -n "$_old_pid" ] && [ -n "$_new_pid" ] && [ "$_old_pid" = "$_new_pid" ] &&
        _gh_pr_resolve_outdated_has_label "$_pr" "$_repo" "$_host" review-passed; then
        # Direct add + marker post — NOT `devx_pr_review_all_write_label`,
        # which also deletes the opposite `review-blocked` label as its first
        # action. This file must never touch that label (see the header note).
        (
            if [ -n "$_host" ]; then
                # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
                export GH_HOST="$_host"
            fi
            _gh_pr_edit_safe_label "$_pr" review-passed --repo "$_repo" >/dev/null 2>&1 &&
                gh api -X POST "repos/$_repo/issues/$_pr/comments" \
                    -f "body=<!-- review-verdict:review-passed:$_new_head -->" >/dev/null 2>&1
        ) || :
        printf 'patch-id=unchanged label=kept marker=reposted\n'
        return 0
    fi

    _gh_pr_drop_label "$_pr" review-passed "$_repo" "$_host" >/dev/null 2>&1 || :
    printf 'patch-id=changed label=dropped\n'
    return 0
}
