#!/usr/bin/env bats
# tests/bats/skills/gh_pr_resolve_ci_fail_review_passed.bats
# Issue #1705 — gh:pr-resolve-ci-fail Step 7 drops a stale `review-passed`:
#   claude/skills/gh-pr-resolve-ci-fail/references/safety.md  (SSOT block)
#   claude/skills/gh-pr-resolve-ci-fail/SKILL.md              (Step 7)
# Source-of-truth fixture: _fixtures/gh_pr_resolve_ci_fail_review_passed.sh
#
# Why this file is so much smaller than its two rebase siblings
# (gh_pr_resolve_{outdated,conflict}_review_passed.bats): those skills can
# reproduce a byte-identical diff under a new SHA, so they reconcile via
# patch-id + the #1601 freshness marker. A CI fix changes file content by
# definition — there is no keep path to test, only an unconditional drop.
# The primitive's own semantics (404 verification, percent-encoding, GH_HOST
# pinning) stay pinned in tests/bats/functions/gh_pr_edit_safe.bats; what this
# file pins is that THIS skill reaches the primitive, with the right label,
# and never widens to `review-blocked`.

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_resolve_ci_fail_review_passed.sh'

setup() {
    setup_isolated_home
    SKILL_DIR="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-resolve-ci-fail"
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : >"$GH_LOG"
    export GH_LOG
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
}

teardown() {
    teardown_isolated_home
}

# Every DELETE succeeds — the ordinary path for a PR that was reviewed green
# and then went red in CI.
_stub_gh_ok() {
    # shellcheck disable=SC2317  # called indirectly by the helper under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        return 0
    }
}

# The DELETE 404s and the verification GET proves `review-passed` is not on the
# PR — but `review-blocked` is. `_gh_pr_drop_label` absorbs this as success.
_stub_gh_absent_but_blocked() {
    # shellcheck disable=SC2317  # called indirectly by the helper under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        case "$*" in
        *"-X DELETE"*)
            printf 'gh: Not Found (HTTP 404)\n' >&2
            return 1
            ;;
        *labels*)
            printf 'CI fail\nreview-blocked\n'
            return 0
            ;;
        esac
        return 0
    }
}

# The DELETE fails and the label IS still on the PR — a genuine failure
# (permissions, 5xx). The only path that may warn.
_stub_gh_fails() {
    # shellcheck disable=SC2317  # called indirectly by the helper under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        case "$*" in
        *"-X DELETE"*)
            printf 'gh: Resource not accessible by integration (HTTP 403)\n' >&2
            return 1
            ;;
        *labels*)
            printf 'review-passed\n'
            return 0
            ;;
        esac
        return 0
    }
}

# ---------------------------------------------------------------------
# The drop itself (#1705)
# ---------------------------------------------------------------------

@test "#1705: a successful CI-fix push drops review-passed from that PR" {
    _stub_gh_ok
    run resolve_ci_fail_step7 99 acme/widget github.com
    assert_success
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/99/labels/review-passed'
}

@test "#1705: the drop reports one line" {
    _stub_gh_ok
    run resolve_ci_fail_step7 99 acme/widget github.com
    assert_output --partial '[OK] `review-passed` 라벨 제거됨'
    assert_output --partial 'CI 수정 커밋으로 head 가 바뀌어 이전 판정 무효화'
}

@test "#1705: the drop is pinned to the target host (#1403 / #1407)" {
    _stub_gh_ok
    resolve_ci_fail_step7 99 acme/widget ghe.example.com
    run cat "$GH_LOG"
    assert_output --partial 'labels/review-passed [GH_HOST=ghe.example.com]'
}

# ---------------------------------------------------------------------
# #1563 — review-blocked is off limits to this skill, always
# ---------------------------------------------------------------------

@test "#1563: review-blocked is never touched, even when attached to the same PR" {
    # Fixing red CI is no evidence a reviewer's blocker was addressed, so the
    # label must survive Step 7 untouched. The stub's verification GET reports
    # `review-blocked` as genuinely attached, so a widened drop would have
    # something real to hit.
    _stub_gh_absent_but_blocked
    run resolve_ci_fail_step7 99 acme/widget github.com
    assert_success
    run cat "$GH_LOG"
    # The skill saw the label in the list...
    assert_output --partial 'api repos/acme/widget/issues/99/labels'
    # ...and still issued no DELETE, POST, or `pr edit` against it.
    refute_output --partial 'labels/review-blocked'
    refute_output --partial 'add-label'
    refute_output --partial 'remove-label'
}

# ---------------------------------------------------------------------
# Soft-fail — the CI fix already landed
# ---------------------------------------------------------------------

@test "soft-fail: a PR that never earned the label warns about nothing" {
    _stub_gh_absent_but_blocked
    run resolve_ci_fail_step7 99 acme/widget github.com
    assert_success
    refute_output --partial '[WARN] `review-passed`'
    assert_output --partial '[OK] PR #99 CI 복구 완료'
}

@test "soft-fail: a genuine delete failure warns but the CI-fix report still prints" {
    _stub_gh_fails
    run resolve_ci_fail_step7 99 acme/widget github.com
    assert_success
    assert_output --partial '[WARN] `review-passed` 라벨 제거 실패'
    assert_output --partial '[OK] PR #99 CI 복구 완료'
}

# ---------------------------------------------------------------------
# Doc guards
# ---------------------------------------------------------------------

@test "doc-guard: SKILL.md Step 7 names the shared helper and the issue" {
    run grep -qF -- '_gh_pr_drop_label' "${SKILL_DIR}/SKILL.md"
    assert_success
    run grep -qF -- '#1705' "${SKILL_DIR}/SKILL.md"
    assert_success
}

@test "doc-guard: safety.md drops review-passed via the shared primitive, unconditionally" {
    local _doc="${SKILL_DIR}/references/safety.md"
    run grep -qF -- '_gh_pr_drop_label "$PR_NUMBER" review-passed' "$_doc"
    assert_success
    run grep -q 'Unconditional' "$_doc"
    assert_success
    # No hand-inlined DELETE for the verdict label — the `CI fail` one above it
    # is the file's only raw `gh api -X DELETE`.
    run grep -c 'gh api -X DELETE' "$_doc"
    assert_output "1"
}

@test "doc-guard: safety.md states review-blocked is never touched (#1563)" {
    local _doc="${SKILL_DIR}/references/safety.md"
    run grep -qF -- 'review-blocked' "$_doc"
    assert_success
    run grep -qF -- '#1563' "$_doc"
    assert_success
}

@test "doc-guard: constraints.md carries the label policy" {
    local _doc="${SKILL_DIR}/references/constraints.md"
    run grep -qF -- 'review-blocked' "$_doc"
    assert_success
    run grep -qF -- 'devx:pr-review-all' "$_doc"
    assert_success
    run grep -qF -- '#1705' "$_doc"
    assert_success
}

@test "doc-guard: the #1563 SSOT lists gh:pr-resolve-ci-fail as a consumer" {
    run grep -qE 'gh:pr-resolve-ci-fail +Step 7' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh"
    assert_success
}
