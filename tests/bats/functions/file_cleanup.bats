#!/usr/bin/env bats
# tests/bats/functions/file_cleanup.bats
# Test file cleanup utility functions.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: del_file function exists" {
    run_in_bash 'declare -f del_file >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: del-file alias exists" {
    run_in_bash 'alias del-file'
    assert_success
}

@test "bash: default patterns include backup/bak/original" {
    run_in_bash '_cleanup_set_default_patterns; for p in "${CLEANUP_DEFAULT_PATTERNS[@]}"; do echo "$p"; done'
    assert_success
    assert_output --partial "backup"
    assert_output --partial "bak"
    assert_output --partial "original"
}

@test "zsh: del_file function exists" {
    run_in_zsh 'declare -f del_file >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: default patterns include backup/bak/original" {
    run_in_zsh '_cleanup_set_default_patterns; for p in "${CLEANUP_DEFAULT_PATTERNS[@]}"; do echo "$p"; done'
    assert_success
    assert_output --partial "backup"
    assert_output --partial "bak"
    assert_output --partial "original"
}
