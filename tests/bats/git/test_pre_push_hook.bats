#!/usr/bin/env bats
# tests/bats/git/test_pre_push_hook.bats
#
# git/hooks/pre-push: protected-branch detection, upstream leak guard
# (T-1 .. T-10, #708) and remote_ref protection (T-11 .. T-13). Case bodies
# live in pre_push_cases.bash (moved from git/tests/test-pre-push.sh, #2163);
# one @test per case. The `mise run test` layer-0 cases are in
# test_pre_push_pytest.bats.

load '../test_helper'
load 'hook_test_env'
load 'pre_push_cases'

setup() {
    hook_test_setup
}

teardown() {
    hook_test_teardown
}

@test "protected branch: master -> BLOCKED" {
    run_test "master" "BLOCKED"
}

@test "protected branch: release/1.0 -> BLOCKED" {
    run_test "release/1.0" "BLOCKED"
}

@test "protected branch: release/2.5.3 -> BLOCKED" {
    run_test "release/2.5.3" "BLOCKED"
}

@test "protected branch: release/v1.0.0 -> BLOCKED" {
    run_test "release/v1.0.0" "BLOCKED"
}

@test "protected branch: main -> ALLOWED" {
    run_test "main" "ALLOWED"
}

@test "protected branch: feature/my-feature -> ALLOWED" {
    run_test "feature/my-feature" "ALLOWED"
}

@test "protected branch: feature/auth-token -> ALLOWED" {
    run_test "feature/auth-token" "ALLOWED"
}

@test "protected branch: develop -> ALLOWED" {
    run_test "develop" "ALLOWED"
}

@test "protected branch: bugfix/urgent -> ALLOWED" {
    run_test "bugfix/urgent" "ALLOWED"
}

@test "protected branch: hotfix/security -> ALLOWED" {
    run_test "hotfix/security" "ALLOWED"
}

@test "protected branch: test/experiment -> ALLOWED" {
    run_test "test/experiment" "ALLOWED"
}

@test "T-1 origin_push_with_pattern_passes" {
    _t1_origin_push_with_pattern_passes
}

@test "T-2 upstream_push_no_pattern_passes" {
    _t2_upstream_push_no_pattern_passes
}

@test "T-3 upstream_push_pattern_in_commit_message_blocks" {
    _t3_upstream_push_pattern_in_commit_message_blocks
}

@test "T-4 upstream_push_pattern_in_diff_blocks" {
    _t4_upstream_push_pattern_in_diff_blocks
}

@test "T-5 skip_leak_guard_escape_hatch" {
    _t5_skip_leak_guard_escape_hatch
}

@test "T-6 skip_pre_push_escape_hatch" {
    _t6_skip_pre_push_escape_hatch
}

@test "T-7 protected_branch_takes_priority" {
    _t7_protected_branch_takes_priority
}

@test "T-8 matching_path_redacted" {
    _t8_matching_path_redacted
}

@test "T-9 matching_path_clean_content_blocks" {
    _t9_matching_path_clean_content_blocks
}

@test "T-10 matching_ref_name_redacted" {
    _t10_matching_ref_name_redacted
}

@test "T-11 renamed_local_to_remote_master_blocks" {
    _t11_renamed_local_to_remote_master_blocks
}

@test "T-12 same_name_feature_push_passes" {
    _t12_same_name_feature_push_passes
}

@test "T-13 delete_remote_master_blocks" {
    _t13_delete_remote_master_blocks
}

@test "G-1 global wrapper execs scripts/hooks/pre-push with argv, stdin, exit code" {
    _g1_scripts_hooks_only_is_exec_with_passthrough
}

@test "G-2 global wrapper: .githooks/ beats scripts/hooks/" {
    _g2_githooks_beats_scripts_hooks
}

@test "G-3 global wrapper: git/hooks/ beats scripts/hooks/" {
    _g3_git_hooks_beats_scripts_hooks
}

@test "G-4 global wrapper skips scripts/hooks/pre-push without exec bit" {
    _g4_scripts_hooks_without_exec_bit_is_skipped
}

@test "G-5 global wrapper skips a scripts/hooks/ self-link (-ef)" {
    _g5_scripts_hooks_self_link_is_skipped
}

@test "G-6 global wrapper is a no-op without a project pre-push" {
    _g6_no_project_hook_is_noop
}
