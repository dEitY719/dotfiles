#!/usr/bin/env bats
# tests/bats/functions/zsh_git_fix.bats
# Unit tests for zsh_git_fix() — gitstatusd repo-detection recovery (issue #968).
# Tests cover all acceptance criteria: alias existence, non-repo guard,
# already-OK early exit, active-worktree abort, and the happy-path fix.

load '../test_helper'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a minimal git repo in TEST_TEMP_HOME/testrepo.
_setup_git_repo() {
    TESTREPO="$TEST_TEMP_HOME/testrepo"
    mkdir -p "$TESTREPO"
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
    git -C "$TESTREPO" init -q --initial-branch=main
    echo base > "$TESTREPO/base.txt"
    git -C "$TESTREPO" add base.txt
    git -C "$TESTREPO" commit -q -m "base"
}

# Simulate the state left by `git worktree add` (the broken state).
_set_worktree_format() {
    git -C "$TESTREPO" config core.repositoryformatversion 1
    git -C "$TESTREPO" config extensions.worktreeConfig true
}

setup() {
    setup_isolated_home
    _setup_git_repo
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Alias + function existence
# ---------------------------------------------------------------------------

@test "bash: zsh-git-fix alias exists" {
    run_in_bash 'alias zsh-git-fix'
    assert_success
}

@test "zsh: zsh-git-fix alias exists" {
    run_in_zsh 'alias zsh-git-fix'
    assert_success
}

@test "bash: zsh_git_fix function exists" {
    run_in_bash 'declare -f zsh_git_fix >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: zsh_git_fix function exists" {
    run_in_zsh 'functions[zsh_git_fix] >/dev/null 2>&1 || declare -f zsh_git_fix >/dev/null; echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Not-a-git-repo guard
# ---------------------------------------------------------------------------

@test "bash: zsh-git-fix returns 1 outside a git repo" {
    run_in_bash "cd '$TEST_TEMP_HOME' && zsh_git_fix 2>&1"
    assert_failure
    assert_output --partial "Not a git repository"
}

@test "zsh: zsh-git-fix returns 1 outside a git repo" {
    run_in_zsh "cd '$TEST_TEMP_HOME' && zsh_git_fix 2>&1"
    assert_failure
    assert_output --partial "Not a git repository"
}

# ---------------------------------------------------------------------------
# Already-OK early exit (repositoryformatversion=0)
# ---------------------------------------------------------------------------

@test "bash: zsh-git-fix prints 'Already OK' when version is already 0" {
    run_in_bash "cd '$TESTREPO' && zsh_git_fix 2>&1"
    assert_success
    assert_output --partial "Already OK"
}

@test "bash: zsh-git-fix does not modify config when already version 0" {
    run_in_bash "cd '$TESTREPO' && zsh_git_fix 2>&1"
    assert_success
    # Config must still be 0 after the call.
    [ "$(git -C "$TESTREPO" config core.repositoryformatversion)" = "0" ]
}

# ---------------------------------------------------------------------------
# Active-worktree abort
# ---------------------------------------------------------------------------

@test "bash: zsh-git-fix aborts when active worktrees are present" {
    _set_worktree_format
    local wt="$TEST_TEMP_HOME/linked-wt"
    git -C "$TESTREPO" worktree add -q -b wt/test "$wt" HEAD

    run_in_bash "cd '$TESTREPO' && zsh_git_fix 2>&1"
    assert_failure
    assert_output --partial "Active worktrees present"

    # .git/config must be unchanged (still version=1).
    [ "$(git -C "$TESTREPO" config core.repositoryformatversion)" = "1" ]

    git -C "$TESTREPO" worktree remove --force "$wt" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Happy-path fix: version=1, no linked worktrees → restore version=0
# ---------------------------------------------------------------------------

@test "bash: zsh-git-fix restores repositoryformatversion to 0" {
    _set_worktree_format

    run_in_bash "cd '$TESTREPO' && zsh_git_fix 2>&1"
    assert_success
    [ "$(git -C "$TESTREPO" config core.repositoryformatversion)" = "0" ]
}

@test "bash: zsh-git-fix removes extensions.worktreeConfig" {
    _set_worktree_format

    run_in_bash "cd '$TESTREPO' && zsh_git_fix 2>&1"
    assert_success
    # extensions.worktreeConfig must be gone (exit non-zero means key absent).
    run git -C "$TESTREPO" config extensions.worktreeConfig
    assert_failure
}

@test "bash: zsh-git-fix prints success and exec-zsh hint" {
    _set_worktree_format

    run_in_bash "cd '$TESTREPO' && zsh_git_fix 2>&1"
    assert_success
    assert_output --partial "Fixed"
    assert_output --partial "exec zsh"
}

@test "zsh: zsh-git-fix restores repositoryformatversion to 0" {
    _set_worktree_format

    run_in_zsh "cd '$TESTREPO' && zsh_git_fix 2>&1"
    assert_success
    [ "$(git -C "$TESTREPO" config core.repositoryformatversion)" = "0" ]
}
