#!/usr/bin/env bats
# tests/bats/git/test_hooks_precommit_checks.bats
#
# Hook integration cases: pre-commit 2-tier delegation and checks (#2014 shellcheck, #2143 registry, #2149 rules moved from golden_rules).
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

@test "test_allows_spaces_in_filename" {
    test_allows_spaces_in_filename
}

@test "test_blocks_forbidden_env_file" {
    test_blocks_forbidden_env_file
}

@test "test_blocks_init_sourcing_tools_custom" {
    test_blocks_init_sourcing_tools_custom
}

@test "test_blocks_auto_exec_custom_script_without_guard" {
    test_blocks_auto_exec_custom_script_without_guard
}

@test "test_blocks_custom_script_wrong_shebang" {
    test_blocks_custom_script_wrong_shebang
}

@test "test_blocks_library_purity_top_level_read" {
    test_blocks_library_purity_top_level_read
}

@test "test_blocks_library_purity_top_level_install" {
    test_blocks_library_purity_top_level_install
}

@test "test_allows_library_purity_commented_install" {
    test_allows_library_purity_commented_install
}

@test "test_blocks_hardcoded_home_path_in_zshrc" {
    test_blocks_hardcoded_home_path_in_zshrc
}

@test "test_allows_hardcoded_home_path_with_marker" {
    test_allows_hardcoded_home_path_with_marker
}

@test "test_allows_home_var_reference" {
    test_allows_home_var_reference
}

@test "test_allows_preexisting_abs_home_on_unrelated_edit" {
    test_allows_preexisting_abs_home_on_unrelated_edit
}

@test "test_shellcheck_blocks_staged_violation" {
    test_shellcheck_blocks_staged_violation
}

@test "test_shellcheck_passes_clean_and_ignores_non_shell" {
    test_shellcheck_passes_clean_and_ignores_non_shell
}

@test "test_wrapper_check_flags_delegating_wrappers" {
    test_wrapper_check_flags_delegating_wrappers
}

@test "test_registry_runs_added_check_file" {
    test_registry_runs_added_check_file
}

@test "test_registry_blocks_invalid_check_file" {
    test_registry_blocks_invalid_check_file
}

@test "test_blocks_emoji_in_main_bash" {
    test_blocks_emoji_in_main_bash
}

@test "test_blocks_model_key_in_claude_settings" {
    test_blocks_model_key_in_claude_settings
}

@test "test_warns_missing_interactive_guard" {
    test_warns_missing_interactive_guard
}
