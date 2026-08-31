#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_reply_review_passed_gate.sh
# Source-of-truth mirror for gh:pr-reply Step 6's `review-passed` gate:
#   claude/skills/gh-pr-reply/references/review-passed-gate.md
#   claude/skills/gh-pr-reply/references/verdict-label-removal.sh.md
#
# Issue #1636 (supersedes the #1616 targeted-re-review fixture this replaces).
# Like the merge-train verdict-gate fixture beside it, this does NOT
# re-implement the gate — it sources the shipped functions, so a mirror cannot
# pass while production drifts (#1524).
#
# Keep the ORDER and the report strings in sync with the doc.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_reply_targeted_review.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/devx_pr_review_all.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_edit_safe.sh"

# Mirrors verdict-label-removal.sh.md + review-passed-gate.md, in order:
#   1. `review-passed` is dropped when (and only when) a push advanced head.
#   2. the severity gate decides whether `review-passed` may be re-applied,
#      from THIS pass's ORIGINS alone — no reviewer CLI is called (#1636).
#   3. the write goes through `_gh_pr_reply_apply_review_passed`, which routes
#      to the shared `devx_pr_review_all_write_label` primitive. There is no
#      inline label command anywhere in this path.
#
# The ORDER of 1 and 2 is load-bearing: swapping them would delete the label
# the gate just applied.
#
# Usage: <origin lines> | pr_reply_step6 <pr> <repo> <host> <head-sha>
#            [<pushed-fixes>]     # default 1
pr_reply_step6() {
    local _pr="$1" _repo="$2" _host="$3" _sha="$4" _pushed="${5-1}"
    local _origins

    _origins=$(cat)

    if [ "$_pushed" -gt 0 ]; then
        _gh_pr_drop_label "$_pr" review-passed "$_repo" "$_host" >/dev/null 2>&1 || :
    fi

    printf '%s\n' "$_origins" |
        _gh_pr_reply_apply_review_passed "$_pr" "$_repo" "$_host" "$_sha"
}
