#!/usr/bin/env bats
# tests/bats/functions/gh_pr_reply.bats
# Smoke tests for the gh-pr-reply orchestrator. These cover the
# pre-spawn surface (loading, help, arg validation, idempotency) — the
# detached-worker pipeline is not exercised here because it would
# require mocking gwt, gh, and claude inside a subshell. That's
# consistent with how gh-flow and gh-pr-approve are tested today.

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

@test "bash: gh_pr_reply function exists" {
    run_in_bash 'declare -f gh_pr_reply >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gh-pr-reply alias resolves to gh_pr_reply" {
    run_in_bash "alias gh-pr-reply 2>/dev/null | grep -q gh_pr_reply && echo ok"
    assert_success
    assert_output --partial "ok"
}

@test "zsh: gh_pr_reply function exists" {
    run_in_zsh 'typeset -f gh_pr_reply >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Help surface (bypasses all preconditions)
# ---------------------------------------------------------------------------

@test "bash: gh-pr-reply with no args prints help" {
    run_in_bash 'gh_pr_reply'
    assert_success
    assert_output --partial "gh-pr-reply"
    assert_output --partial "pr-number"
}

@test "bash: gh-pr-reply --help prints help" {
    run_in_bash 'gh_pr_reply --help'
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "gh-pr-reply"
}

@test "bash: gh-pr-reply -h prints help" {
    run_in_bash 'gh_pr_reply -h'
    assert_success
}

@test "bash: help documents parallel usage and state dir" {
    # The help must describe the two things that distinguish this from
    # running /gh-pr-reply manually: parallelism and the state dir.
    # If either is missing, users lose the discoverability the feature
    # was designed around.
    run_in_bash 'gh_pr_reply --help 2>&1'
    assert_success
    assert_output --partial "parallel"
    assert_output --partial "state"
}

@test "bash: help documents teardown-skip on failure" {
    # The defining behavior vs gh-pr-approve: the skill edits files +
    # commits + pushes, and on failure the worktree is preserved so
    # local commits aren't lost. If this guarantee disappears from
    # help, users may delete worktrees thinking they're empty.
    run_in_bash 'gh_pr_reply --help 2>&1'
    assert_success
    assert_output --partial "preserved"
}

# ---------------------------------------------------------------------------
# Argument validation — must fail before any spawn attempt
# ---------------------------------------------------------------------------

@test "bash: non-integer PR number is rejected" {
    # 'abc' is obviously not a PR number. The function must reject it
    # rather than hand it to gwt and produce a confusing failure later.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_reply abc 2>&1"
    assert_failure
    assert_output --partial "invalid"
}

@test "bash: mixed valid + invalid args reject the batch" {
    # Fail-fast: one bad arg in the list aborts the whole batch. This
    # matches gh-flow / gh-pr-approve behavior and prevents half-spawned
    # state.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_reply 42 notanumber 2>&1"
    assert_failure
    assert_output --partial "invalid"
}

@test "bash: '#' prefix on PR number is accepted (ergonomic)" {
    # Same ergonomic deviation as gh-pr-approve. PR numbers are written
    # as #N in conversation, so both forms work. We can't run the worker
    # in tests, but we can at least prove the validator accepts '#42' —
    # the error, if any, must come later than the 'invalid PR number'
    # check.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_reply '#42' 2>&1 || true"
    refute_output --partial "invalid PR number"
}

@test "bash: rejects run from inside a worktree" {
    # The orchestrator must refuse to spawn from a worktree — workers
    # would otherwise create worktrees-of-worktrees, which gwt doesn't
    # support. Same guard as gh-flow / gh-pr-approve.
    (
        cd "$FAKE_REPO"
        git worktree add -q -b test-wt "$TEST_TEMP_HOME/fake-wt" 2>/dev/null
    )
    run_in_bash "cd '$TEST_TEMP_HOME/fake-wt' && gh_pr_reply 42 2>&1"
    assert_failure
    assert_output --partial "main repo"
}

# ---------------------------------------------------------------------------
# Idempotency — failed runs must not be auto-resumed
# ---------------------------------------------------------------------------

@test "bash: refuses to auto-resume a previously failed run" {
    # Distinguishing behavior of gh-pr-reply vs gh-pr-approve. Because
    # the skill commits and pushes, a failed worker may leave unpushed
    # local commits in the worktree. Re-spawning would re-run gwt spawn,
    # which is a no-op (worktree already exists) but would also re-run
    # the skill — fine in itself, but if the user hasn't yet recovered
    # the prior commits, automation noise drowns the warning. So instead
    # we refuse and tell the user to inspect + clear state explicitly.
    # XDG_STATE_HOME is not exported to run_in_bash subprocesses, so the
    # function falls back to $HOME/.local/state. setup_isolated_home set
    # HOME to TEST_TEMP_HOME, and FAKE_REPO basename is 'fake-main'.
    local _state_dir="$HOME/.local/state/gh-pr-reply/fake-main/42"
    mkdir -p "$_state_dir"
    printf 'failed:replying\n' >"$_state_dir/state"
    run_in_bash "cd '$FAKE_REPO' && gh_pr_reply 42 2>&1"
    assert_success
    assert_output --partial "previous run failed"
    assert_output --partial "rm -rf"
}
