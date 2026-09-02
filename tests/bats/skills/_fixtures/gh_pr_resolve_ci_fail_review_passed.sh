#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_resolve_ci_fail_review_passed.sh
# Source-of-truth mirror for gh:pr-resolve-ci-fail Step 7's `review-passed`
# drop:
#   claude/skills/gh-pr-resolve-ci-fail/references/safety.md  (SSOT block)
#   claude/skills/gh-pr-resolve-ci-fail/SKILL.md              (Step 7)
#
# Issue #1705. Like the fixtures beside it, this does NOT re-implement the
# DELETE — it sources the shipped `gh_pr_edit_safe.sh` and calls the shared
# `_gh_pr_drop_label` primitive, so a mirror cannot pass while production
# drifts (#1524's rule).
#
# No patch-id / marker machinery here on purpose: unlike the two rebase
# skills, this drop is unconditional (a CI fix changes content by definition).
#
# Keep the report strings in sync with the doc.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_edit_safe.sh"

# Mirrors the safety.md block verbatim.
#
# Usage: resolve_ci_fail_step7_drop_review_passed <pr> <repo> <host>
resolve_ci_fail_step7_drop_review_passed() {
    # shellcheck disable=SC2016  # backticks are markdown in the message
    _gh_pr_drop_label "$1" review-passed "$2" "${3-}" \
        >/dev/null 2>&1 \
      && printf '[OK] `review-passed` 라벨 제거됨 — CI 수정 커밋으로 head 가 바뀌어 이전 판정 무효화\n' \
      || printf '[WARN] `review-passed` 라벨 제거 실패 (권한/네트워크 — 수동 확인 필요할 수 있음)\n'
    return 0
}

# Step 7 in the SKILL's order: `CI fail` removal, then the `review-passed`
# drop, then the report — which must print on every path, since both label
# mutations are soft-fail.
#
# Usage: resolve_ci_fail_step7 <pr> <repo> <host>
resolve_ci_fail_step7() {
    local _pr="$1" _repo="$2" _host="$3"
    # shellcheck disable=SC2016  # backticks are markdown in the message
    GH_HOST="$_host" gh api -X DELETE "repos/$_repo/issues/$_pr/labels/CI%20fail" \
        >/dev/null 2>&1 \
      && printf '[OK] `CI fail` 라벨 제거됨 — 동료 재-Approve 흐름 해제\n' \
      || printf '[WARN] `CI fail` 라벨 제거 실패 (이미 없거나 권한 없음 — 수동 제거 필요할 수 있음)\n'
    resolve_ci_fail_step7_drop_review_passed "$_pr" "$_repo" "$_host"
    printf '[OK] PR #%s CI 복구 완료\n' "$_pr"
    return 0
}
