#!/usr/bin/env bats
# tests/bats/skills/gh_issue_implement_claim.bats
# Verify the Step 3 substep gating documented in
#   claude/skills/gh-issue-implement/references/claim.md
# Source-of-truth fixture: _fixtures/gh_issue_implement_claim.sh
#
# Eight cases drawn from issue #391's behavior matrix (case 8 from #1507):
#   1. Normal flow (board, unassigned, deps OK)         → all proceed
#   2. Block-label attached                             → guard rc=2
#   3. Already self-assigned                            → noop-self
#   4. Assigned to another user                         → warn-other
#   5. Dependency M still OPEN                          → deps warn
#   6. No board attached                                → board skip
#   7. GH_ISSUE_SKIP_* env vars individually skip       → matching branch
#   8. Duplicate-attempt detection (#1507)              → soft [WARN], never blocks
#      8a. open PR already closes the issue             → warn naming the PR
#      8b. no open PR                                   → silent (no false positive)
#      8c. GH_ISSUE_SKIP_DUPLICATE_CHECK=1              → silent
#      8d. search API failure                           → silent, still rc=0
#      8e. board Status already "In progress"           → warn + already-in-progress

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_implement_claim.sh"
}

teardown() {
    teardown_isolated_home
    unset FAKE_LABELS FAKE_ASSIGNEES FAKE_ME FAKE_BODY \
          FAKE_DEPS_STATES FAKE_BOARD_ATTACHED FAKE_BOARD_STATUS \
          FAKE_OPEN_PRS_CLOSING FAKE_DUPLICATE_PR_API_FAIL \
          GH_ISSUE_BLOCK_LABELS \
          GH_ISSUE_SKIP_SELF_ASSIGN \
          GH_ISSUE_SKIP_BOARD_TRANSITION \
          GH_ISSUE_SKIP_DEPS_CHECK \
          GH_ISSUE_SKIP_DUPLICATE_CHECK
}

# ---------- Case 1: Normal flow ----------

@test "claim: normal flow — no block label, unassigned, board attached, deps OK" {
    FAKE_LABELS="feat,p1"
    FAKE_ASSIGNEES=""
    FAKE_ME="alice"
    FAKE_BODY="# Goal\n\nDo the thing.\n\nDepends on #100"
    FAKE_DEPS_STATES="100:CLOSED"
    FAKE_BOARD_ATTACHED=1
    FAKE_OPEN_PRS_CLOSING=""
    FAKE_BOARD_STATUS="Ready"

    run gh_issue_block_label_guard 391
    assert_success

    run gh_issue_self_assign_decide
    assert_success
    assert_output 'add'

    run gh_issue_duplicate_pr_guard 391
    assert_success
    assert_output ''

    run gh_issue_board_transition_decide
    assert_success
    assert_output 'synced'

    run gh_issue_deps_guard 391
    assert_success
    refute_output --partial '⚠️'
}

# ---------- Case 2: Block-label attached ----------

@test "claim: block-label 'on-hold' → guard rc=2 with refusal text" {
    FAKE_LABELS="feat,on-hold"
    run gh_issue_block_label_guard 391
    [ "$status" -eq 2 ]
    assert_output --partial 'Refusing to start #391'
    assert_output --partial 'on-hold'
}

@test "claim: block-label '보류' (Korean) matches default list" {
    FAKE_LABELS="보류"
    run gh_issue_block_label_guard 391
    [ "$status" -eq 2 ]
    assert_output --partial '보류'
}

@test "claim: GH_ISSUE_BLOCK_LABELS override — only listed labels block" {
    GH_ISSUE_BLOCK_LABELS="parking"
    # default block words must NOT trigger when override is set
    FAKE_LABELS="on-hold"
    run gh_issue_block_label_guard 391
    assert_success

    FAKE_LABELS="parking"
    run gh_issue_block_label_guard 391
    [ "$status" -eq 2 ]
}

# ---------- Case 3: Already self-assigned ----------

@test "claim: self already in assignee list → 'noop-self'" {
    FAKE_ASSIGNEES="alice,bob"
    FAKE_ME="alice"
    run gh_issue_self_assign_decide
    assert_success
    assert_output 'noop-self'
}

# ---------- Case 4: Assigned to another user ----------

@test "claim: only other users assigned → 'warn-other' (no override)" {
    FAKE_ASSIGNEES="bob"
    FAKE_ME="alice"
    run gh_issue_self_assign_decide
    assert_success
    assert_output 'warn-other'
}

# ---------- Case 5: Dependency M still OPEN ----------

@test "claim: depends-on with OPEN M → soft warn line emitted" {
    FAKE_BODY="Goal here.\n\nDepends on #200"
    FAKE_DEPS_STATES="200:OPEN"
    run gh_issue_deps_guard 391
    assert_success    # soft
    assert_output --partial '⚠️'
    assert_output --partial '#200'
    assert_output --partial 'OPEN'
}

@test "claim: depends-on case-insensitive match (lowercase 'depends on')" {
    FAKE_BODY="depends on #201"
    FAKE_DEPS_STATES="201:OPEN"
    run gh_issue_deps_guard 391
    assert_success
    assert_output --partial '#201'
}

@test "claim: depends-on multiple deps — only OPEN ones warn" {
    FAKE_BODY=$'Depends on #100\nDepends on #101\nDepends on #102'
    FAKE_DEPS_STATES="100:CLOSED,101:OPEN,102:CLOSED"
    run gh_issue_deps_guard 391
    assert_success
    assert_output --partial '#101'
    refute_output --partial '#100'
    refute_output --partial '#102'
}

# ---------- Case 6: No board attached ----------

@test "claim: no projectV2 attached → board branch returns 'no-board'" {
    FAKE_BOARD_ATTACHED=0
    run gh_issue_board_transition_decide
    assert_success
    assert_output 'no-board'
}

# ---------- Case 7: GH_ISSUE_SKIP_* env vars ----------

@test "claim: GH_ISSUE_SKIP_SELF_ASSIGN=1 → 'skip' regardless of assignees" {
    FAKE_ASSIGNEES=""
    FAKE_ME="alice"
    GH_ISSUE_SKIP_SELF_ASSIGN=1 run gh_issue_self_assign_decide
    assert_success
    assert_output 'skip'
}

@test "claim: GH_ISSUE_SKIP_BOARD_TRANSITION=1 → 'skip' even with board attached" {
    FAKE_BOARD_ATTACHED=1
    GH_ISSUE_SKIP_BOARD_TRANSITION=1 run gh_issue_board_transition_decide
    assert_success
    assert_output 'skip'
}

@test "claim: GH_ISSUE_SKIP_DEPS_CHECK=1 → no warn even with OPEN dep" {
    FAKE_BODY="Depends on #999"
    FAKE_DEPS_STATES="999:OPEN"
    GH_ISSUE_SKIP_DEPS_CHECK=1 run gh_issue_deps_guard 391
    assert_success
    refute_output --partial '⚠️'
}

# ---------- Case 8: Duplicate-attempt detection (#1507) ----------

@test "claim 3.3b: open PR already closing the issue → soft [WARN] naming the PR" {
    FAKE_OPEN_PRS_CLOSING="1488"
    run gh_issue_duplicate_pr_guard 1482
    assert_success    # soft — never blocks
    assert_output --partial '[WARN]'
    assert_output --partial '#1482'
    assert_output --partial '#1488'
}

@test "claim 3.3b: first PR of several is the one named" {
    FAKE_OPEN_PRS_CLOSING="1488,1489"
    run gh_issue_duplicate_pr_guard 1482
    assert_success
    assert_output --partial '#1488'
}

@test "claim 3.3b: no open PR closing the issue → silent (no false positive)" {
    FAKE_OPEN_PRS_CLOSING=""
    run gh_issue_duplicate_pr_guard 1482
    assert_success
    assert_output ''
}

@test "claim 3.3b: GH_ISSUE_SKIP_DUPLICATE_CHECK=1 → silent even with an open PR" {
    FAKE_OPEN_PRS_CLOSING="1488"
    GH_ISSUE_SKIP_DUPLICATE_CHECK=1 run gh_issue_duplicate_pr_guard 1482
    assert_success
    assert_output ''
}

@test "claim 3.3b: search API failure → soft-fail, silent, still success" {
    FAKE_OPEN_PRS_CLOSING="1488"
    FAKE_DUPLICATE_PR_API_FAIL=1 run gh_issue_duplicate_pr_guard 1482
    assert_success
    assert_output ''
}

@test "claim 3.4: board Status already 'In progress' → warn + 'already-in-progress'" {
    FAKE_BOARD_ATTACHED=1
    FAKE_BOARD_STATUS="In progress"
    run gh_issue_board_transition_decide 1482
    assert_success
    assert_output --partial '[WARN]'
    assert_output --partial '#1482'
    assert_output --partial 'In progress'
    assert_output --partial 'already-in-progress'
}

@test "claim 3.4: board Status Backlog/Ready → unchanged 'synced', no warn" {
    FAKE_BOARD_ATTACHED=1
    FAKE_BOARD_STATUS="Backlog"
    run gh_issue_board_transition_decide 1482
    assert_success
    assert_output 'synced'

    FAKE_BOARD_STATUS="Ready"
    run gh_issue_board_transition_decide 1482
    assert_success
    assert_output 'synced'
}

@test "claim 3.4: no board attached → 'no-board' wins over FAKE_BOARD_STATUS" {
    FAKE_BOARD_ATTACHED=0
    FAKE_BOARD_STATUS="In progress"
    run gh_issue_board_transition_decide 1482
    assert_success
    assert_output 'no-board'
}
