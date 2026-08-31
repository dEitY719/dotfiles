#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_merge_review_passed_cleanup.sh
# Source-of-truth mirror for gh:pr-merge Step 4's post-merge label cleanup:
#   claude/skills/gh-pr-merge/references/review-passed-cleanup.sh.md
#   claude/skills/gh-pr-merge/SKILL.md  (Step 4 -> Step 5 ordering)
#
# Issue #1636, F-5. Like the fixtures beside it, this does NOT re-implement the
# delete — it sources the shipped `gh_pr_edit_safe.sh` and calls the shared
# `_gh_pr_drop_label` primitive, so a mirror cannot pass while production
# drifts (#1524's rule).
#
# Keep the ORDER and the WARN string in sync with the doc.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_edit_safe.sh"

# Mirrors review-passed-cleanup.sh.md verbatim. Soft-fail is the contract: the
# merge already happened, so a failed delete costs one `[WARN]` line and
# nothing else — never an exit status, never a retry.
#
# Usage: merge_review_passed_cleanup <pr> <repo> <host>
merge_review_passed_cleanup() {
    local _pr="$1" _repo="$2" _host="$3" _rpc_err
    if _rpc_err=$(_gh_pr_drop_label "$_pr" review-passed "$_repo" "$_host" 2>&1); then
        : # removed, or verifiably never there — both are success, stay quiet
    else
        # shellcheck disable=SC2016  # backticks are markdown in the message
        printf '[WARN] merge 후 `review-passed` 정리 실패 — 머지 자체는 성공: %s\n' "$_rpc_err"
    fi
    return 0
}

# Step 4 (housekeeping) then Step 5 (report), in the SKILL's order. The report
# must print on every path — that is what "soft-fail" means here.
#
# Usage: merge_step4_then_report <pr> <repo> <host>
merge_step4_then_report() {
    merge_review_passed_cleanup "$@"
    printf '[OK] PR #%s merged\n' "$1"
    return 0
}
