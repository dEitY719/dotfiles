#!/usr/bin/env bats
# tests/bats/git/test_hooks_global_wrappers.bats
#
# Hook integration cases: global wrapper delegation for pre-push and friends (#1664).
# Case bodies live in hook_cases.bash (moved from git/tests/test_hooks.sh,
# #2163); one @test per case.

load '../test_helper'
load 'hook_test_env'
load 'hook_cases'

setup() {
    hook_test_setup
}

teardown() {
    hook_test_teardown
}

@test "test_global_hook_set_matches_ssot" {
    test_global_hook_set_matches_ssot
}

@test "test_global_pre_push_delegates_to_project_hook" {
    test_global_pre_push_delegates_to_project_hook
}

@test "test_global_pre_push_is_noop_in_unrelated_repo" {
    test_global_pre_push_is_noop_in_unrelated_repo
}

@test "test_global_pre_push_delegates_from_linked_worktree" {
    test_global_pre_push_delegates_from_linked_worktree
}

@test "test_global_wrappers_delegate_argv" {
    test_global_wrappers_delegate_argv
}

@test "test_global_wrappers_propagate_exit_code" {
    test_global_wrappers_propagate_exit_code
}

@test "test_global_wrappers_are_noop_without_project_hook" {
    test_global_wrappers_are_noop_without_project_hook
}

@test "test_global_wrappers_are_noop_outside_git_repo" {
    test_global_wrappers_are_noop_outside_git_repo
}
