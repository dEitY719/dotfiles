#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_push_policy.sh
# Source-of-truth mirror for the Step 1b branch-state block documented in
#   claude/skills/gh-pr/references/branch-state.md
# (and the push-policy table in references/push-and-create.md).
#
# Two concerns live here, matching issue #1315:
#   F-1  upstream / branch-name mispair → the push action must be
#        `push -u origin HEAD`, never a bare `push`.
#   F-2  the session started on the base branch → auto-create a feature
#        branch, then rewind the local base only when the guard allows.
#
# Everything is pure string/set logic, so the bats suite exercises it with
# plain arguments — no live git, no live gh.
#
# Keep this file in sync with references/branch-state.md. If the skill
# block changes, mirror the change here so the bats suite catches drift.

# ── F-1: upstream pairing ──────────────────────────────────────────────
gh_pr_normalize_upstream() {
    local _u="${1-}"
    _u="${_u#refs/remotes/}"
    printf '%s' "$_u"
}

gh_pr_upstream_is_mispaired() {
    local _upstream _current="${2-}"
    _upstream=$(gh_pr_normalize_upstream "${1-}")
    [ -n "$_upstream" ] || return 1
    [ -n "$_current" ] || return 1
    [ "$_upstream" = "origin/$_current" ] && return 1
    return 0
}

gh_pr_push_action() {
    local _current="${1-}" _upstream="${2-}" _diverged="${3-}"

    if [ -z "$(gh_pr_normalize_upstream "$_upstream")" ]; then
        printf 'push -u origin HEAD\n'
        return 0
    fi
    # F-1 — checked BEFORE divergence: a mispaired branch's ahead/behind is
    # measured against the wrong ref, so "diverged" cannot be trusted yet.
    if gh_pr_upstream_is_mispaired "$_upstream" "$_current"; then
        printf 'push -u origin HEAD\n'
        return 0
    fi
    if [ "$_diverged" = "diverged" ]; then
        printf 'STOP\n'
        return 0
    fi
    printf 'push\n'
}

# ── F-2: branch naming ─────────────────────────────────────────────────
gh_pr_commit_type() {
    local _title="${1-}" _type
    _type=$(printf '%s' "$_title" |
        sed -n 's/^\([a-z][a-z]*\)\(([^)]*)\)\{0,1\}!\{0,1\}:.*/\1/p')
    case "$_type" in
        feat|fix|refactor|perf|docs|test|chore|style|build|ci|revert) ;;
        *) _type=chore ;;
    esac
    printf '%s' "$_type"
}

gh_pr_branch_name() {
    local _type="${1-}" _issue="${2-}" _date="${3-}" _sha="${4-}"
    case "$_type" in
        feat|fix|refactor|perf|docs|test|chore|style|build|ci|revert) ;;
        *) _type=chore ;;
    esac
    if printf '%s' "$_issue" | grep -qE '^[1-9][0-9]*$'; then
        printf '%s/issue-%s\n' "$_type" "$_issue"
        return 0
    fi
    printf '%s/%s-%s\n' "$_type" "$_date" "$_sha"
}

# ── F-2: base-branch recovery decision + rewind guard ──────────────────
_gh_pr_normalize_sha_set() {
    printf '%s\n' "${1-}" | tr -s '[:space:]' '\n' | grep -E '^[0-9a-fA-F]+$' | sort -u
}

_gh_pr_set_contains() {
    local _set="${1-}" _needle="${2-}" _item
    for _item in $_set; do
        [ "$_item" = "$_needle" ] && return 0
    done
    return 1
}

gh_pr_base_branch_decision() {
    local _current="${1-}" _base="${2-}"
    local _local_only _moved _on_origin _sha

    if [ "$_current" != "$_base" ]; then
        printf 'not-on-base\n'
        return 0
    fi

    _local_only=$(_gh_pr_normalize_sha_set "${3-}")
    _moved=$(_gh_pr_normalize_sha_set "${4-}")
    _on_origin=$(_gh_pr_normalize_sha_set "${5-}")

    if [ -z "$_local_only" ]; then
        printf 'nothing-to-pr\n'
        return 0
    fi

    for _sha in $_moved; do
        if _gh_pr_set_contains "$_on_origin" "$_sha"; then
            printf 'stop-already-pushed\n'
            return 0
        fi
    done

    if [ "$_local_only" = "$_moved" ]; then
        printf 'auto-branch-and-rewind\n'
    else
        printf 'auto-branch-warn-only\n'
    fi
}
