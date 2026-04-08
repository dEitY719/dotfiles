#!/usr/bin/env bats
# tests/bats/init/sourcing.bats
# Verify shell-common sourcing mechanism works correctly.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# --- bash ---

@test "bash: main.bash sets SHELL_COMMON variable" {
    run_in_bash 'test -n "$SHELL_COMMON" && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: main.bash sets DOTFILES_ROOT variable" {
    run_in_bash 'test -n "$DOTFILES_ROOT" && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: SOURCED_FILES_COUNT is greater than 0" {
    run_in_bash 'test "$SOURCED_FILES_COUNT" -gt 0 && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: aliases are loaded (my-help)" {
    run_in_bash 'alias my-help'
    assert_success
}

@test "bash: functions are loaded (my_help_impl)" {
    run_in_bash 'declare -f my_help_impl >/dev/null && echo ok'
    assert_success
}

@test "bash: functions are loaded (del_file)" {
    run_in_bash 'declare -f del_file >/dev/null && echo ok'
    assert_success
}

@test "bash: functions are loaded (git_log)" {
    run_in_bash 'declare -f git_log >/dev/null && echo ok'
    assert_success
}

# --- zsh ---

@test "zsh: main.zsh sets SHELL_COMMON variable" {
    run_in_zsh 'test -n "$SHELL_COMMON" && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: main.zsh sets DOTFILES_ROOT variable" {
    run_in_zsh 'test -n "$DOTFILES_ROOT" && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: SOURCED_FILES_COUNT is greater than 0" {
    run_in_zsh 'test "$SOURCED_FILES_COUNT" -gt 0 && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: aliases are loaded (my-help)" {
    run_in_zsh 'alias my-help'
    assert_success
}

@test "zsh: functions are loaded (my_help_impl)" {
    run_in_zsh 'declare -f my_help_impl >/dev/null && echo ok'
    assert_success
}
