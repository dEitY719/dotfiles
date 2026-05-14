#!/usr/bin/env bats
# tests/bats/skills/gh_pr_stacked_detect.bats
# Verify the Step 1a stacked-PR auto-detect logic documented in
#   claude/skills/gh-pr/references/stacked-pr.md
# Source-of-truth fixture: _fixtures/gh_pr_stacked_detect.sh.
#
# 8-case compatibility matrix (issue #615 trimmed the prior 9-case set):
#   1. dotfiles solo (no stacked signals)        → Stage 1 fail, base=default
#   2. AgentToolbox parent unique                → Stage 1+2, 1 candidate
#   3. AgentToolbox parent ambiguous             → Stage 1+2, 2+ candidates
#   4. AgentToolbox no parent (root issue)       → Stage 1 pass, 0 candidates
#   5. --no-stack override                       → mode=no-stack
#   6. --base <branch> override                  → mode=base
#   7. Mutually-exclusive flags (--no-stack + --base) → rc=2 abort
#   8. --base (missing arg)                      → rc=3 abort

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_stacked_detect.sh"
    REPO_ROOT="$(mktemp -d)"
}

teardown() {
    [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT" ] && rm -rf "$REPO_ROOT"
    unset FAKE_OPEN_PRS FAKE_ANCESTOR_REFS FAKE_NONDEFAULT_REFS
    unset STACK_MODE STACK_BASE ISSUE_NUMBER
    teardown_isolated_home
}

# ── 1. Stage 1: solo / no signals ─────────────────────────────────────
@test "stage1: empty repo (no signals) → not stacked (rc=1)" {
    run is_stacked_pr_repo "$REPO_ROOT"
    [ "$status" -eq 1 ]
}

# ── 2/3/4. Stage 1: each signal is detected ───────────────────────────
@test "stage1: workflow file → stacked" {
    mkdir -p "$REPO_ROOT/.github/workflows"
    touch    "$REPO_ROOT/.github/workflows/stacked-closes-rollup.yml"
    run is_stacked_pr_repo "$REPO_ROOT"
    assert_success
}

@test "stage1: CLAUDE.md keyword → stacked" {
    printf 'see claude-enter-issue for details\n' > "$REPO_ROOT/CLAUDE.md"
    run is_stacked_pr_repo "$REPO_ROOT"
    assert_success
}

@test "stage1: AGENTS.md 'Depends on #' → stacked" {
    printf 'use Depends on # in PR bodies\n' > "$REPO_ROOT/AGENTS.md"
    run is_stacked_pr_repo "$REPO_ROOT"
    assert_success
}

@test "stage1: agent-toolbox/ dir → stacked" {
    mkdir -p "$REPO_ROOT/agent-toolbox"
    run is_stacked_pr_repo "$REPO_ROOT"
    assert_success
}

@test "stage1: .claude/github-integration.md keyword → stacked" {
    mkdir -p "$REPO_ROOT/.claude"
    printf 'Backlog 중복 검사: stacked PR 정책\n' > "$REPO_ROOT/.claude/github-integration.md"
    run is_stacked_pr_repo "$REPO_ROOT"
    assert_success
}

@test "stage1: keyword absent in CLAUDE.md → not stacked" {
    printf 'just a regular project doc\n' > "$REPO_ROOT/CLAUDE.md"
    run is_stacked_pr_repo "$REPO_ROOT"
    [ "$status" -eq 1 ]
}

# ── Compatibility matrix #1: dotfiles solo invocation ─────────────────
# parse_stacked_args sets globals; bats `run` would fork a subshell and lose
# them, so we invoke directly. A non-zero rc trips bats's test-body errexit.
@test "matrix-1: dotfiles solo / no flags → mode=auto, no override" {
    parse_stacked_args
    [ "$STACK_MODE" = "auto" ]
    [ -z "$STACK_PARENT" ]
    [ -z "$STACK_BASE" ]
}

# ── Compatibility matrix #2: AgentToolbox parent unique ───────────────
@test "matrix-2: stage2 with single ancestor PR → 1 candidate line" {
    FAKE_OPEN_PRS=$'201 feat/parent-branch\n205 feat/sibling-branch'
    FAKE_ANCESTOR_REFS='origin/feat/parent-branch'
    FAKE_NONDEFAULT_REFS='origin/feat/parent-branch'
    run find_parent_pr_candidates main
    assert_success
    assert_output --partial '201:feat/parent-branch'
    refute_output --partial '205:'
}

# ── Compatibility matrix #3: AgentToolbox parent ambiguous ────────────
@test "matrix-3: stage2 with two ancestor PRs → 2 candidate lines" {
    FAKE_OPEN_PRS=$'201 feat/parent-a\n205 feat/parent-b\n300 feat/orphan'
    FAKE_ANCESTOR_REFS='origin/feat/parent-a origin/feat/parent-b'
    FAKE_NONDEFAULT_REFS='origin/feat/parent-a origin/feat/parent-b'
    run find_parent_pr_candidates main
    assert_success
    assert_output --partial '201:feat/parent-a'
    assert_output --partial '205:feat/parent-b'
    refute_output --partial '300:'
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

# ── Compatibility matrix #4: AgentToolbox no parent ───────────────────
@test "matrix-4: stage2 with zero ancestor PRs → empty output" {
    FAKE_OPEN_PRS=$'201 feat/unrelated-a\n205 feat/unrelated-b'
    FAKE_ANCESTOR_REFS=''
    FAKE_NONDEFAULT_REFS=''
    run find_parent_pr_candidates main
    assert_success
    [ -z "$output" ]
}

@test "matrix-4b: stage2 candidate with same merge-base as default → dropped" {
    # PR head is an ancestor of HEAD but its merge-base equals the default's
    # — i.e. it doesn't actually advance the parent search. Must be skipped.
    FAKE_OPEN_PRS='201 feat/same-as-default'
    FAKE_ANCESTOR_REFS='origin/feat/same-as-default'
    FAKE_NONDEFAULT_REFS=''
    run find_parent_pr_candidates main
    assert_success
    [ -z "$output" ]
}

# ── Compatibility matrix #5: --no-stack ───────────────────────────────
@test "matrix-5: --no-stack → STACK_MODE=no-stack" {
    parse_stacked_args --no-stack
    [ "$STACK_MODE" = "no-stack" ]
}

# ── Compatibility matrix #6: --base <branch> ──────────────────────────
@test "matrix-6: --base release/v2.0 → STACK_MODE=base, STACK_BASE=release/v2.0" {
    parse_stacked_args --base release/v2.0
    [ "$STACK_MODE" = "base" ]
    [ "$STACK_BASE" = "release/v2.0" ]
}

# ── Compatibility matrix #7: mutually-exclusive flags ─────────────────
@test "matrix-7: --no-stack --base main → rc=2 with explanatory message" {
    run parse_stacked_args --no-stack --base main
    [ "$status" -eq 2 ]
    assert_output --partial 'mutually exclusive'
}

# ── Compatibility matrix #8: --base missing branch arg ────────────────
@test "matrix-8: --base (no arg) → rc=3 with explanatory message" {
    run parse_stacked_args --base
    [ "$status" -eq 3 ]
    assert_output --partial 'requires a branch name'
}

# ── Legacy positional issue arg still parsed ──────────────────────────
@test "parse: positional integer arg → ISSUE_NUMBER (legacy /gh-pr 123)" {
    parse_stacked_args 123
    [ "$STACK_MODE" = "auto" ]
    [ "$ISSUE_NUMBER" = "123" ]
}

@test "parse: positional integer + --no-stack → both bound" {
    parse_stacked_args 42 --no-stack
    [ "$STACK_MODE" = "no-stack" ]
    [ "$ISSUE_NUMBER" = "42" ]
}
