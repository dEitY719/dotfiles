#!/usr/bin/env bats
# tests/bats/skills/gh_pr_approve_board_sync.bats
# Verify the Step 4.5 promotion into `Approved`.
# Source-of-truth fixture: _fixtures/gh_pr_approve_board_sync.sh.
#
# #1680: the gh-pr-approve / gh-pr-reply skills moved out to their own
# marketplace repos, so the three doc-guards that grepped
# claude/skills/** were dropped and belong in that repo now. The fixture
# below is therefore no longer pinned to a SKILL.md — it stands alone as
# the behavioural contract.
#
# Issue #1350: ownership of the `Approved` column moved here from
# gh:pr-reply Step 8 (deleted). Cases:
#   1. approve path (no bypass)          → helper called, bypass unset
#   2. --self-record path (bypass=1)     → helper called with bypass=1 + audit line
#   3. bypass does not leak to caller    → prefix form scoping contract
#   4. helper rc=2                       → soft-fail WARN, rc=0
#   5. --only-from "Backlog,In progress,In review" guard on every call

load '../test_helper'

setup() {
    setup_isolated_home
    FAKE_HELPER_LOG="$(mktemp)"
    export FAKE_HELPER_LOG
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_approve_board_sync.sh"
}

teardown() {
    teardown_isolated_home
    [ -n "$FAKE_HELPER_LOG" ] && rm -f "$FAKE_HELPER_LOG"
    unset FAKE_HELPER_LOG FAKE_HELPER_RC _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS
}

@test "board-approve: approve path calls helper WITHOUT the #393 bypass" {
    run gh_pr_approve_board_sync_step45 1349 0 owner/repo
    assert_success
    refute_output --partial 'bypassing #393'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called bypass=unset'
    assert_output --partial 'args=pr 1349 Approved --only-from Backlog,In progress,In review --repo owner/repo'
}

@test "board-approve: --self-record path calls helper WITH bypass=1 + audit line" {
    run gh_pr_approve_board_sync_step45 1349 1 owner/repo
    assert_success
    assert_output --partial 'self-record: bypassing #393 fail-closed guard for PR #1349'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called bypass=1'
    assert_output --partial 'args=pr 1349 Approved --only-from Backlog,In progress,In review --repo owner/repo'
}

@test "board-approve: bypass env var does NOT leak to caller scope" {
    # The prefix form `_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 helper`
    # must scope the binding to that single call. `env VAR=val funcname`
    # cannot be used — the helper is a shell function, not a binary.
    unset _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS
    gh_pr_approve_board_sync_step45 1349 1 owner/repo >/dev/null 2>&1
    [ -z "${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS-}" ]
}

@test "board-approve: helper rc=2 → soft-fail warn, rc=0" {
    FAKE_HELPER_RC=2
    run gh_pr_approve_board_sync_step45 1349 1 owner/repo
    assert_success
    assert_output --partial 'board sync rc=2 — continuing (soft-fail)'
}

@test "board-approve: --only-from pre-merge whitelist is present on both paths" {
    # `Done` is deliberately absent: without the guard, a re-review on an
    # already-merged PR would drag the `Done` card backwards into
    # `Approved`. The three allowed origins mirror
    # .github/workflows/project-board-sync.yml's approve handler, so the
    # skill path never refuses a promotion the workflow path would make.
    gh_pr_approve_board_sync_step45 1349 0 owner/repo >/dev/null 2>&1
    gh_pr_approve_board_sync_step45 1349 1 owner/repo >/dev/null 2>&1
    run cat "$FAKE_HELPER_LOG"
    assert_success
    [ "$(grep -c -- '--only-from Backlog,In progress,In review' "$FAKE_HELPER_LOG")" = "2" ]
}

@test "board-approve (#1405): both paths pass the explicit --repo" {
    # Without --repo the helper resolves the repo through `gh repo view`,
    # which answers `gh repo set-default` rather than the remote Step 1
    # resolved — the wrong board on a multi-repo host.
    gh_pr_approve_board_sync_step45 1349 0 owner/repo >/dev/null 2>&1
    gh_pr_approve_board_sync_step45 1349 1 owner/repo >/dev/null 2>&1
    [ "$(grep -c -- '--repo owner/repo' "$FAKE_HELPER_LOG")" = "2" ]
}
