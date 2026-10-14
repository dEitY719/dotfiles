#!/usr/bin/env bats
# tests/bats/git/test_hooks_leak_guard.bats
#
# Hook integration cases: commit-time leak guard (#1970).
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

@test "test_leak_guard_blocks_without_echoing_match" {
    test_leak_guard_blocks_without_echoing_match
}

@test "test_leak_guard_redacts_matching_path" {
    test_leak_guard_redacts_matching_path
}

@test "test_leak_guard_redacts_other_check_reports" {
    test_leak_guard_redacts_other_check_reports
}

@test "test_leak_guard_redacts_global_and_project_output" {
    test_leak_guard_redacts_global_and_project_output
}

@test "test_global_hook_leak_guard_in_unrelated_repo" {
    test_global_hook_leak_guard_in_unrelated_repo
}

@test "test_leak_guard_inert_without_upstream_remote" {
    test_leak_guard_inert_without_upstream_remote
}

@test "test_leak_guard_skip_escape_hatch" {
    test_leak_guard_skip_escape_hatch
}
