#!/usr/bin/env bats
# tests/bats/functions/git.bats
# Test git utility functions.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# --- function existence ---

@test "bash: git_log function exists" {
    run_in_bash 'declare -f git_log >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_log_upstream function exists" {
    run_in_bash 'declare -f git_log_upstream >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_prune_remote function exists" {
    run_in_bash 'declare -f git_prune_remote >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_clean_local function exists" {
    run_in_bash 'declare -f git_clean_local >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gl alias exists" {
    run_in_bash 'alias gl'
    assert_success
    assert_output --partial "git-log"
}

# --- git worktree functions ---

@test "bash: gwt function exists" {
    run_in_bash 'declare -f gwt >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_worktree_list function exists" {
    run_in_bash 'declare -f git_worktree_list >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_worktree_add function exists" {
    run_in_bash 'declare -f git_worktree_add >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_worktree_remove function exists" {
    run_in_bash 'declare -f git_worktree_remove >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# --- git_ssh_check ---

@test "bash: git_ssh_check function exists" {
    run_in_bash 'declare -f git_ssh_check >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git-ssh-check alias exists" {
    run_in_bash 'alias git-ssh-check'
    assert_success
}

# --- git_log output (in a git repo) ---

@test "bash: git_log produces output in git repo" {
    run_in_bash "cd '${DOTFILES_ROOT}' && git_log"
    assert_success
}

# --- zsh parity ---

@test "zsh: git_log function exists" {
    run_in_zsh 'declare -f git_log >/dev/null && echo ok'
    assert_success
}

@test "zsh: gwt function exists" {
    run_in_zsh 'declare -f gwt >/dev/null && echo ok'
    assert_success
}

@test "zsh: git_ssh_check function exists" {
    run_in_zsh 'declare -f git_ssh_check >/dev/null && echo ok'
    assert_success
}
