#!/usr/bin/env bats
# tests/bats/skills/gh_pr_reply_board_sync.bats
# Verify the Step 6.5 board-sync (`In review` 복귀) gate documented in
#   claude/skills/gh-pr-reply/SKILL.md  (Step 6.5)
# Source-of-truth fixture: _fixtures/gh_pr_reply_board_sync.sh.
#
# Five cases drawn from issue #627's acceptance criteria:
#   1. push happened (PUSHED_FIXES > 0)            → helper called + audit OK line
#   2. no push (PUSHED_FIXES == 0)                 → silent no-op
#   3. PUSHED_FIXES unset                          → silent no-op (default 0)
#   4. helper returns 2 (already In review etc.)   → WARN line, rc=0 (soft-fail)
#   5. argv carries --only-from "In progress,Changes requested" guard

load '../test_helper'

setup() {
    setup_isolated_home
    FAKE_HELPER_LOG="$(mktemp)"
    export FAKE_HELPER_LOG
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_reply_board_sync.sh"
}

teardown() {
    teardown_isolated_home
    [ -n "$FAKE_HELPER_LOG" ] && rm -f "$FAKE_HELPER_LOG"
    unset FAKE_HELPER_LOG FAKE_HELPER_RC
}

@test "board-sync: PUSHED_FIXES>0 → helper called, OK line" {
    run gh_pr_reply_board_sync_step65 663 2
    assert_success
    assert_output --partial 'In review'
    assert_output --partial '[OK] PR'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called'
    assert_output --partial 'args=pr 663 In review --only-from In progress,Changes requested'
}

@test "board-sync: PUSHED_FIXES=0 → silent no-op" {
    run gh_pr_reply_board_sync_step65 663 0
    assert_success
    refute_output --partial '[OK]'
    refute_output --partial '[WARN]'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "board-sync: PUSHED_FIXES unset → silent no-op (default 0)" {
    run gh_pr_reply_board_sync_step65 663 ""
    assert_success
    refute_output --partial '[OK]'
    refute_output --partial '[WARN]'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "board-sync: helper rc=2 → WARN line, rc=0 (soft-fail)" {
    FAKE_HELPER_RC=2
    run gh_pr_reply_board_sync_step65 663 1
    assert_success
    assert_output --partial '[WARN] 보드 sync 실패'
    refute_output --partial '[OK] PR'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called'
}

@test "board-sync: argv carries --only-from guard (regression: don't demote cards already past In review)" {
    # The `--only-from "In progress,Changes requested"` filter is the
    # safety belt that prevents accidentally demoting cards already at
    # `In review` / `Approved` / `Done`. Drop it and a re-run after
    # approval would push the card backwards.
    run gh_pr_reply_board_sync_step65 663 5
    assert_success
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial '--only-from In progress,Changes requested'
}
