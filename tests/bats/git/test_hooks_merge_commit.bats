#!/usr/bin/env bats
# tests/bats/git/test_hooks_merge_commit.bats
#
# Hook integration cases: git sync merge commits pass the hooks (#2041).
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

@test "test_commit_msg_skips_git_merge_message" {
    test_commit_msg_skips_git_merge_message
}

@test "test_main_branch_guard_allows_merge_in_progress" {
    test_main_branch_guard_allows_merge_in_progress
}
