#!/usr/bin/env bats
# tests/bats/skills/gh_pr_resolve_ci_fail_review_passed.bats
# Issue #1705 — gh:pr-resolve-ci-fail Step 5 drops a stale `review-passed`
# immediately after the push (moved out of Step 7 by #1711, codex review
# BLOCKER — see below).
# Source-of-truth fixture: _fixtures/gh_pr_resolve_ci_fail_review_passed.sh
# (the skill's SKILL.md / references/ left this repo with #1680, so the fixture
# is no longer pinned to them)
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
#
# #1711 (codex review of PR #1711, BLOCKER): the original #1705 landing put
# the drop in Step 7, after Step 6's optional `--wait`. A re-review completing
# during that wait could grant a genuinely fresh `review-passed` for the new
# head, and the deferred drop would then delete a verdict that was correct at
# the moment it ran. The ordering tests below pin that the drop now runs
# before Step 7 — i.e. before `--wait` ever gets a chance to run.

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_resolve_ci_fail_review_passed.sh'

setup() {
    setup_isolated_home
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
    run resolve_ci_fail_step5_drop_review_passed 99 acme/widget github.com
    assert_success
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/99/labels/review-passed'
}

@test "#1705: the drop reports one line" {
    _stub_gh_ok
    run resolve_ci_fail_step5_drop_review_passed 99 acme/widget github.com
    assert_output --partial '[OK] `review-passed` 라벨 제거됨'
    assert_output --partial 'CI 수정 커밋으로 head 가 바뀌어 이전 판정 무효화'
}

@test "#1705: the drop is pinned to the target host (#1403 / #1407)" {
    _stub_gh_ok
    resolve_ci_fail_step5_drop_review_passed 99 acme/widget ghe.example.com
    run cat "$GH_LOG"
    assert_output --partial 'labels/review-passed [GH_HOST=ghe.example.com]'
}

# ---------------------------------------------------------------------
# #1711 — the drop must run BEFORE Step 7 (i.e. before Step 6's --wait
# ever gets a chance to run), closing the race a deferred drop opened.
# ---------------------------------------------------------------------

@test "#1711: the review-passed drop precedes the CI-fail label removal in the call log" {
    _stub_gh_ok
    resolve_ci_fail_step5_through_7 99 acme/widget github.com
    run cat "$GH_LOG"
    assert_success
    # The review-passed DELETE must appear before the CI-fail DELETE — if
    # a --wait had run between them, this is the exact window (#1711).
    local _rp_line _ci_line
    _rp_line=$(grep -n 'labels/review-passed' "$GH_LOG" | head -1 | cut -d: -f1)
    _ci_line=$(grep -n 'labels/CI%20fail' "$GH_LOG" | head -1 | cut -d: -f1)
    [ -n "$_rp_line" ]
    [ -n "$_ci_line" ]
    [ "$_rp_line" -lt "$_ci_line" ]
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
    run resolve_ci_fail_step5_drop_review_passed 99 acme/widget github.com
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
    run resolve_ci_fail_step5_through_7 99 acme/widget github.com
    assert_success
    refute_output --partial '[WARN] `review-passed`'
    assert_output --partial '[OK] PR #99 CI 복구 완료'
}

@test "soft-fail: a genuine delete failure warns but the CI-fix report still prints" {
    _stub_gh_fails
    run resolve_ci_fail_step5_through_7 99 acme/widget github.com
    assert_success
    assert_output --partial '[WARN] `review-passed` 라벨 제거 실패'
    assert_output --partial '[OK] PR #99 CI 복구 완료'
}

# ---------------------------------------------------------------------
# Doc guards — only the shell SSOT one survives (#1680)
# ---------------------------------------------------------------------
#
# gh-pr-resolve-ci-fail's SKILL.md and references/ (safety.md, constraints.md)
# moved out to their own marketplace repo, so the guards that pinned them to
# the fixture above belong there. The fixture mirror stays as real, runnable
# behaviour — it is simply no longer pinned to any doc in this repo.

@test "doc-guard: the #1563 SSOT lists gh:pr-resolve-ci-fail as a consumer" {
    run grep -qE 'gh:pr-resolve-ci-fail +Step 5' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh"
    assert_success
}
