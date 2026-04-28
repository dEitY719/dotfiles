#!/usr/bin/env bats
# tests/bats/functions/gh_pr_approve.bats
# Smoke tests for the gh-pr-approve orchestrator. These cover the
# pre-spawn surface (loading, help, arg validation) — the detached-worker
# pipeline is not exercised here because it would require mocking gwt,
# gh, and claude inside a subshell. That's consistent with how gh-flow
# (the sibling feature) is tested today.

load '../test_helper'

# Spin up a throwaway main repo so arg-validation tests don't trip the
# "must run from main repo" precondition check — the bats host repo is
# itself a worktree, which would short-circuit the validator.
_setup_fake_main_repo() {
    FAKE_REPO="$TEST_TEMP_HOME/fake-main"
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
    git init -q --initial-branch=main "$FAKE_REPO"
    (
        cd "$FAKE_REPO"
        echo base >base.txt
        git add base.txt
        git commit -q -m base
    )
}

setup() {
    setup_isolated_home
    _setup_fake_main_repo
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

@test "bash: gh_pr_approve function exists" {
    run_in_bash 'declare -f gh_pr_approve >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gh-pr-approve alias resolves to gh_pr_approve" {
    run_in_bash "alias gh-pr-approve 2>/dev/null | grep -q gh_pr_approve && echo ok"
    assert_success
    assert_output --partial "ok"
}

@test "zsh: gh_pr_approve function exists" {
    run_in_zsh 'typeset -f gh_pr_approve >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Help surface (bypasses all preconditions)
# ---------------------------------------------------------------------------

@test "bash: gh-pr-approve with no args prints help" {
    run_in_bash 'gh_pr_approve'
    assert_success
    assert_output --partial "gh-pr-approve"
    assert_output --partial "pr-number"
}

@test "bash: gh-pr-approve --help prints help" {
    run_in_bash 'gh_pr_approve --help'
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "gh-pr-approve"
}

@test "bash: gh-pr-approve -h prints help" {
    run_in_bash 'gh_pr_approve -h'
    assert_success
}

@test "bash: help documents parallel usage and state dir" {
    # The help must describe the two things that distinguish this from
    # running /gh-pr-approve manually: parallelism and the state dir.
    # If either is missing, users lose the discoverability the feature
    # was designed around.
    run_in_bash 'gh_pr_approve --help 2>&1'
    assert_success
    assert_output --partial "parallel"
    assert_output --partial "state"
}

# ---------------------------------------------------------------------------
# Argument validation — must fail before any spawn attempt
# ---------------------------------------------------------------------------

@test "bash: non-integer PR number is rejected" {
    # 'abc' is obviously not a PR number. The function must reject it
    # rather than hand it to gwt and produce a confusing failure later.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve abc 2>&1"
    assert_failure
    assert_output --partial "invalid"
}

@test "bash: mixed valid + invalid args reject the batch" {
    # Fail-fast: one bad arg in the list aborts the whole batch. This
    # matches gh-flow's behavior and prevents half-spawned state.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 notanumber 2>&1"
    assert_failure
    assert_output --partial "invalid"
}

@test "bash: '#' prefix on PR number is accepted (ergonomic)" {
    # Ergonomic deviation from gh-flow (which requires pure integers).
    # PR numbers are written as #N in conversation, so both forms work.
    # We can't run the worker in tests, but we can at least prove the
    # validator accepts '#42' — the error, if any, must come later than
    # the 'invalid PR number' check.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve '#42' 2>&1 || true"
    refute_output --partial "invalid PR number"
}

@test "bash: rejects run from inside a worktree" {
    # The orchestrator must refuse to spawn from a worktree — workers
    # would otherwise create worktrees-of-worktrees, which gwt doesn't
    # support. This is the same guard gh-flow enforces.
    (
        cd "$FAKE_REPO"
        git worktree add -q -b test-wt "$TEST_TEMP_HOME/fake-wt" 2>/dev/null
    )
    run_in_bash "cd '$TEST_TEMP_HOME/fake-wt' && gh_pr_approve 42 2>&1"
    assert_failure
    assert_output --partial "main repo"
}

# ---------------------------------------------------------------------------
# --ai option (mirrors gh-flow #208 contract)
# ---------------------------------------------------------------------------

@test "help: documents --ai option and supported runners" {
    # The whole point of #214 is discoverability — if --ai isn't surfaced
    # in help, users will keep assuming claude is the only option.
    run_in_bash 'gh_pr_approve --help'
    assert_success
    assert_output --partial "--ai"
    assert_output --partial "claude (default) | codex | gemini"
}

@test "help: documents self-PR modes" {
    run_in_bash 'gh_pr_approve --help'
    assert_success
    assert_output --partial "--self-record"
    assert_output --partial "--admin-merge"
}

@test "bash: '--ai codex' parses (precondition fails on missing codex CLI, not parser)" {
    # We can't easily fake the codex/gemini CLI here, so we assert the
    # parser accepted the value and produced a precondition-shaped error
    # rather than the generic 'unknown option' or 'invalid --ai value'
    # parser errors.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --ai codex 2>&1 || true"
    refute_output --partial "unknown option"
    refute_output --partial "invalid --ai value"
}

@test "bash: '--ai gemini' parses with leading position" {
    # --ai may appear before PR numbers — position-agnostic.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve --ai gemini 42 2>&1 || true"
    refute_output --partial "unknown option"
    refute_output --partial "invalid --ai value"
    refute_output --partial "invalid PR number"
}

@test "bash: trailing '42 --ai codex' is accepted" {
    # Regression guard: --ai after PR numbers must be parsed, not
    # treated as a stray PR number.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --ai codex 2>&1 || true"
    refute_output --partial "invalid PR number: '--ai'"
}

@test "bash: '--ai' without value fails with clear message" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --ai 2>&1"
    assert_failure
    assert_output --partial "missing value for --ai"
    assert_output --partial "claude|codex|gemini"
}

@test "bash: invalid --ai value is rejected" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --ai bogus 2>&1"
    assert_failure
    assert_output --partial "invalid --ai value"
    assert_output --partial "claude|codex|gemini"
}

@test "bash: unknown long option is rejected" {
    # Anything starting with '-' that isn't --ai/--ai=... should be
    # rejected up-front rather than reaching the PR-number validator.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve --bogus 42 2>&1"
    assert_failure
    assert_output --partial "unknown option"
}

# ---------------------------------------------------------------------------
# self-PR options
# ---------------------------------------------------------------------------

@test "bash: legacy --self-ok is rejected with server-side guidance" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --self-ok 2>&1"
    assert_failure
    assert_output --partial "--self-ok is not supported"
    assert_output --partial "server-side"
}

@test "bash: '--self-record' parses as a self-PR mode" {
    run_in_bash "cd '$FAKE_REPO' && PATH=/nonexistent gh_pr_approve 42 --self-record 2>&1 || true"
    refute_output --partial "unknown option"
    refute_output --partial "invalid PR number"
}

@test "bash: '--admin-merge --squash' parses as a self-PR mode" {
    run_in_bash "cd '$FAKE_REPO' && PATH=/nonexistent gh_pr_approve 42 --admin-merge --squash 2>&1 || true"
    refute_output --partial "unknown option"
    refute_output --partial "invalid PR number"
}

@test "bash: merge strategy flags require --admin-merge" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --squash 2>&1"
    assert_failure
    assert_output --partial "--squash requires --admin-merge"
}
