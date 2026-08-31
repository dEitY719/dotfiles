#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_review_passed_cleanup.bats
# Issue #1636, F-5 — gh:pr-merge drops `review-passed` after a successful
# merge:
#   claude/skills/gh-pr-merge/references/review-passed-cleanup.sh.md  (SSOT)
#   claude/skills/gh-pr-merge/SKILL.md  (Step 4)
# Source-of-truth fixture: _fixtures/gh_pr_merge_review_passed_cleanup.sh
#
# Why the label is dropped at all: it is a claim about one head commit of an
# OPEN PR, read only by `gh:pr-merge-train`'s gate. After the merge nothing
# reads it, and leaving it on makes a reopened PR look pre-verified.
#
# Why every test here also asserts the report: this is a post-merge cleanup.
# The merge already succeeded, so no failure of this step may change the
# report or the exit status (#1636 Error Cases).

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_merge_review_passed_cleanup.sh'

setup() {
    setup_isolated_home
    SKILL_DIR="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge"
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : >"$GH_LOG"
    export GH_LOG
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
}

teardown() {
    teardown_isolated_home
}

# The DELETE succeeds — the ordinary path for a PR that earned the label.
_stub_gh_ok() {
    # shellcheck disable=SC2317  # called indirectly by the helper under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        return 0
    }
}

# The DELETE fails and the verification GET proves the label is NOT on the
# PR — i.e. it was never applied. `_gh_pr_drop_label` absorbs this as success.
_stub_gh_absent() {
    # shellcheck disable=SC2317  # called indirectly by the helper under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        case "$*" in
        *"-X DELETE"*)
            printf 'gh: Not Found (HTTP 404)\n' >&2
            return 1
            ;;
        *labels*)
            printf 'conflict\n'
            return 0
            ;;
        esac
        return 0
    }
}

# The DELETE fails and the label IS still on the PR — a genuine failure
# (permissions, 5xx). This is the only path that may warn.
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
# F-5 — the drop itself
# ---------------------------------------------------------------------

@test "F-5: a successful merge drops review-passed from that PR" {
    _stub_gh_ok
    run merge_step4_then_report 51 acme/widget github.com
    assert_success
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/51/labels/review-passed'
}

@test "F-5: the drop is pinned to the target host (#1403 / #1407)" {
    _stub_gh_ok
    merge_step4_then_report 51 acme/widget ghe.example.com
    run cat "$GH_LOG"
    assert_output --partial 'labels/review-passed [GH_HOST=ghe.example.com]'
}

@test "F-5: review-blocked is never touched" {
    # A merged PR cannot be blocked, and this step has no verdict of its own —
    # widening the cleanup would make it an invalidation it is not.
    _stub_gh_ok
    merge_step4_then_report 51 acme/widget github.com
    run cat "$GH_LOG"
    refute_output --partial 'review-blocked'
}

@test "F-5: the report still prints after a successful drop" {
    _stub_gh_ok
    run merge_step4_then_report 51 acme/widget github.com
    assert_success
    assert_output --partial '[OK] PR #51 merged'
}

# ---------------------------------------------------------------------
# Soft-fail — the merge already happened
# ---------------------------------------------------------------------

@test "soft-fail: a genuine delete failure warns but the merge report still prints" {
    _stub_gh_fails
    run merge_step4_then_report 51 acme/widget github.com
    assert_success
    assert_output --partial 'merge 후 `review-passed` 정리 실패'
    assert_output --partial '머지 자체는 성공'
    assert_output --partial '[OK] PR #51 merged'
}

@test "soft-fail: a delete failure never changes the exit status" {
    _stub_gh_fails
    run merge_step4_then_report 51 acme/widget github.com
    assert_success
}

@test "soft-fail: the WARN carries gh's original error, not a paraphrase" {
    _stub_gh_fails
    run merge_step4_then_report 51 acme/widget github.com
    assert_output --partial 'HTTP 403'
}

@test "idempotent: a PR that never earned the label warns about nothing" {
    _stub_gh_absent
    run merge_step4_then_report 51 acme/widget github.com
    assert_success
    refute_output --partial '[WARN]'
    assert_output --partial '[OK] PR #51 merged'
}

@test "idempotent: the absent-label path still verifies against the real list" {
    # #1583's rule: a 404 is not trusted on its own — the helper asks the PR
    # for its actual labels before calling the delete a no-op.
    _stub_gh_absent
    merge_step4_then_report 51 acme/widget github.com
    run cat "$GH_LOG"
    assert_output --partial 'api repos/acme/widget/issues/51/labels'
}

# ---------------------------------------------------------------------
# Doc guards
# ---------------------------------------------------------------------

@test "doc-guard: SKILL.md Step 4 runs the cleanup and names the shared helper" {
    run grep -qF -- 'review-passed-cleanup.sh.md' "${SKILL_DIR}/SKILL.md"
    assert_success
    run grep -qF -- '_gh_pr_drop_label' "${SKILL_DIR}/SKILL.md"
    assert_success
}

@test "doc-guard: SKILL.md marks the cleanup soft-fail" {
    run grep -q 'soft-fail' "${SKILL_DIR}/SKILL.md"
    assert_success
    run grep -qF -- '#1636' "${SKILL_DIR}/SKILL.md"
    assert_success
}

@test "doc-guard: the cleanup doc uses the shared primitive, never an inline DELETE" {
    local _doc="${SKILL_DIR}/references/review-passed-cleanup.sh.md"
    run grep -qF -- '_gh_pr_drop_label' "$_doc"
    assert_success
    run grep -qE 'gh api -X DELETE' "$_doc"
    assert_failure
}

@test "doc-guard: the cleanup doc explains it is cleanup, not invalidation" {
    local _doc="${SKILL_DIR}/references/review-passed-cleanup.sh.md"
    run grep -q 'not an invalidation' "$_doc"
    assert_success
    run grep -qF -- '#1636' "$_doc"
    assert_success
}

@test "doc-guard: the #1563 SSOT lists gh:pr-merge as a consumer of the primitive" {
    run grep -qE 'gh:pr-merge +Step 4' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh"
    assert_success
}
