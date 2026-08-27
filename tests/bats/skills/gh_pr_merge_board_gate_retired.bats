#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_board_gate_retired.bats
# Issue #1513 — gh:pr-merge's Step 2-B board-approval gate was removed:
# it was permanently un-satisfiable on this repo (no branch protection,
# every PR self-authored, agy/codex reviews post as COMMENTED so
# reviewDecision never changes). This is a doc-level drift guard, not a
# behavioural test — gh:pr-merge is a Claude-driven skill, not a shell
# function, so the only thing bats can pin here is that the retired gate
# does not silently reappear in the skill's own instructions (codex
# review, PR #1516: deleting the old gate's bats suite left no regression
# test pinning the new "board Status is not a merge gate" contract).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "retired (#1513): board-approval-gate.sh.md no longer exists" {
    run test -f "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge/references/board-approval-gate.sh.md"
    assert_failure
}

@test "retired (#1513): gh-pr-merge SKILL.md does not re-declare a Step 2-B board gate" {
    run grep -F "Step 2-B: Project Board Approval Gate" \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge/SKILL.md"
    assert_failure
}

@test "retired (#1513): gh-pr-merge SKILL.md pins the new contract — board Status is not a merge gate" {
    run grep -F "not** a merge gate (#1513)" \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge/SKILL.md"
    assert_success
}

@test "retired (#1513): gh-pr-merge-train no longer routes a PR through the board-status gate" {
    # train-loop.md legitimately still mentions "Step 2-B" once, in its own
    # retirement note ("Step 2-B board check was removed in #1513") — that
    # reference is fine. What must be gone is the *active* SKIPPED-reason
    # phrasing that named it as a gate to detect and route around.
    run grep -RF "gh:pr-merge Step 2-B)" \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/"
    assert_failure
}

@test "retired (#1513): GH_PR_MERGE_SKIP_BOARD_CHECK is not documented as a live escape hatch" {
    # The env-vars catalog and board-policy.md are allowed to mention the name
    # historically (marked retired) — this guard targets the one place a live
    # escape hatch would actually be *used*: gh-pr-merge's own SKILL.md.
    run grep -F "GH_PR_MERGE_SKIP_BOARD_CHECK" \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge/SKILL.md"
    assert_failure
}
