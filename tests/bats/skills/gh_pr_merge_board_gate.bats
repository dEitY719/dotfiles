#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_board_gate.bats
# Verify the Step 4-B board approval gate documented in
#   claude/skills/gh-pr-merge/SKILL.md
# Source-of-truth fixture: _fixtures/gh_pr_merge_board_gate.sh.
#
# Five cases drawn from issue #397's acceptance criteria:
#   1. board Status == "Approved"        → rc=0 (proceed)
#   2. board Status == "In review"       → rc=2 (refuse + redirect)
#   3. board Status empty (no board)     → rc=0 (silent skip)
#   4. GH_PR_MERGE_SKIP_BOARD_CHECK=1    → rc=0 (escape, no read needed)
#   5. board Status == "In progress"     → rc=2 (any non-Approved fails closed)

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_merge_board_gate.sh"
}

teardown() {
    teardown_isolated_home
    unset FAKE_BOARD_STATUS GH_PR_MERGE_SKIP_BOARD_CHECK
}

@test "board-gate: Status=Approved → rc=0 (proceed silently)" {
    FAKE_BOARD_STATUS="Approved"
    run gh_pr_merge_board_gate 42 owner/repo
    assert_success
    refute_output --partial "Refusing"
}

@test "board-gate: Status=In review → rc=2 with redirect message" {
    FAKE_BOARD_STATUS="In review"
    run gh_pr_merge_board_gate 42 owner/repo
    [ "$status" -eq 2 ]
    assert_output --partial 'Refusing to merge PR #42'
    assert_output --partial 'board Status is "In review"'
    assert_output --partial '/gh-pr-merge-emergency'
    assert_output --partial 'GH_PR_MERGE_SKIP_BOARD_CHECK=1'
}

@test "board-gate: empty Status (no projectV2 attached) → rc=0 silently skips" {
    FAKE_BOARD_STATUS=""
    run gh_pr_merge_board_gate 42 owner/repo
    assert_success
    refute_output --partial "Refusing"
}

@test "board-gate: GH_PR_MERGE_SKIP_BOARD_CHECK=1 bypasses gate" {
    # Even with a clearly-violating status, the env-var escape lets the
    # operator merge — this matches the documented in-transition workflow.
    FAKE_BOARD_STATUS="In review"
    GH_PR_MERGE_SKIP_BOARD_CHECK=1 run gh_pr_merge_board_gate 42 owner/repo
    assert_success
    refute_output --partial "Refusing"
}

@test "board-gate: Status=In progress (any non-Approved) → rc=2" {
    # Verifies the gate is fail-closed, not whitelisted to specific values.
    # In progress, Backlog, Done, and any custom column all fail closed.
    FAKE_BOARD_STATUS="In progress"
    run gh_pr_merge_board_gate 42 owner/repo
    [ "$status" -eq 2 ]
    assert_output --partial 'board Status is "In progress"'
}
