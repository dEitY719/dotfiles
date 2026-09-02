#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_resolve_ci_fail_review_passed.sh
# Source-of-truth mirror for gh:pr-resolve-ci-fail's `review-passed` drop:
#   claude/skills/gh-pr-resolve-ci-fail/references/safety.md  (SSOT block,
#     under "Step 5 push")
#   claude/skills/gh-pr-resolve-ci-fail/SKILL.md              (Step 5)
#
# Issue #1705, timing fixed by #1711 (codex review, BLOCKER): the drop runs
# right after Step 5's push succeeds — NOT deferred to Step 7 — because Step
# 6's optional `--wait` can poll for minutes with the head unchanged, and a
# re-review completing in that window could grant a genuinely fresh
# `review-passed` for that exact head. Dropping before Step 6 ever starts
# closes the window: Step 7 (CI-fail label removal) is a separate,
# independent mutation that never touches `review-passed`.
#
# Like the fixtures beside it, this does NOT re-implement the DELETE — it
# sources the shipped `gh_pr_edit_safe.sh` and calls the shared
# `_gh_pr_drop_label` primitive, so a mirror cannot pass while production
# drifts (#1524's rule).
#
# No patch-id / marker machinery here on purpose: unlike the two rebase
# skills, this drop is unconditional (a CI fix changes content by definition).
#
# Keep the report strings in sync with the doc.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_edit_safe.sh"

# Mirrors the safety.md "review-passed drop" block verbatim — runs
# immediately after Step 5's push, independent of Step 7.
#
# Usage: resolve_ci_fail_step5_drop_review_passed <pr> <repo> <host>
resolve_ci_fail_step5_drop_review_passed() {
    # shellcheck disable=SC2016  # backticks are markdown in the message
    _gh_pr_drop_label "$1" review-passed "$2" "${3-}" \
        >/dev/null 2>&1 \
      && printf '[OK] `review-passed` 라벨 제거됨 — CI 수정 커밋으로 head 가 바뀌어 이전 판정 무효화\n' \
      || printf '[WARN] `review-passed` 라벨 제거 실패 (권한/네트워크 — 수동 확인 필요할 수 있음)\n'
    return 0
}

# Step 7 — CI-fail label removal only. Does NOT touch review-passed (that
# already ran back in Step 5, independent of whether --wait fired in between).
#
# Usage: resolve_ci_fail_step7 <pr> <repo> <host>
resolve_ci_fail_step7() {
    local _pr="$1" _repo="$2" _host="$3"
    # shellcheck disable=SC2016  # backticks are markdown in the message
    GH_HOST="$_host" gh api -X DELETE "repos/$_repo/issues/$_pr/labels/CI%20fail" \
        >/dev/null 2>&1 \
      && printf '[OK] `CI fail` 라벨 제거됨 — 동료 재-Approve 흐름 해제\n' \
      || printf '[WARN] `CI fail` 라벨 제거 실패 (이미 없거나 권한 없음 — 수동 제거 필요할 수 있음)\n'
    printf '[OK] PR #%s CI 복구 완료\n' "$_pr"
    return 0
}

# Full flow in the SKILL's actual order: Step 5 push already happened
# (caller's job), so this starts at the review-passed drop, then simulates
# Step 6 (--wait, a no-op here) having elapsed, then Step 7. Used by the
# regression test that pins the ORDER, not just the outcome (#1711).
#
# Usage: resolve_ci_fail_step5_through_7 <pr> <repo> <host>
resolve_ci_fail_step5_through_7() {
    local _pr="$1" _repo="$2" _host="$3"
    resolve_ci_fail_step5_drop_review_passed "$_pr" "$_repo" "$_host"
    resolve_ci_fail_step7 "$_pr" "$_repo" "$_host"
    return 0
}
