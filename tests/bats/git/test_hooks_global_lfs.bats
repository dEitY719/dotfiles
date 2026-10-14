#!/usr/bin/env bats
# tests/bats/git/test_hooks_global_lfs.bats
#
# Hook integration cases: git-lfs chaining in the global wrappers (lib/lfs.sh).
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

@test "test_global_lfs_pre_push_chains_and_replays_stdin" {
    test_global_lfs_pre_push_chains_and_replays_stdin
}

@test "test_global_lfs_pre_push_failure_blocks" {
    test_global_lfs_pre_push_failure_blocks
}

@test "test_global_lfs_pre_push_project_failure_skips_lfs" {
    test_global_lfs_pre_push_project_failure_skips_lfs
}

@test "test_global_lfs_post_hooks_chain" {
    test_global_lfs_post_hooks_chain
}

@test "test_global_lfs_post_hook_failure_without_project_hook" {
    test_global_lfs_post_hook_failure_without_project_hook
}

@test "test_global_lfs_chains_in_linked_worktree" {
    test_global_lfs_chains_in_linked_worktree
}

@test "test_global_lfs_detected_via_tracked_gitattributes" {
    test_global_lfs_detected_via_tracked_gitattributes
}

@test "test_global_lfs_skipped_in_non_lfs_repo" {
    test_global_lfs_skipped_in_non_lfs_repo
}

@test "test_global_lfs_not_doubled_by_lfs_project_hook" {
    test_global_lfs_not_doubled_by_lfs_project_hook
}
