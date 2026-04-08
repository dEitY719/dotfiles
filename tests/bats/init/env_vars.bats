#!/usr/bin/env bats
# tests/bats/init/env_vars.bats
# Verify environment variables are correctly set after initialization.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# --- bash ---

@test "bash: DOTFILES_ROOT points to correct path" {
    run_in_bash "echo \$DOTFILES_ROOT"
    assert_success
    assert_output --partial "$DOTFILES_ROOT"
}

@test "bash: SHELL_COMMON equals DOTFILES_ROOT/shell-common" {
    run_in_bash 'echo "$SHELL_COMMON"'
    assert_success
    assert_output --partial "${DOTFILES_ROOT}/shell-common"
}

@test "bash: PATH contains .local/bin" {
    run_in_bash 'echo "$PATH" | tr ":" "\n" | grep -q ".local/bin" && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: EDITOR is set" {
    run_in_bash 'test -n "$EDITOR" && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: init succeeds without .local files" {
    run_in_bash 'echo ok'
    assert_success
    assert_output --partial "ok"
}

# --- zsh ---

@test "zsh: DOTFILES_ROOT points to correct path" {
    run_in_zsh "echo \$DOTFILES_ROOT"
    assert_success
    assert_output --partial "$DOTFILES_ROOT"
}

@test "zsh: SHELL_COMMON equals DOTFILES_ROOT/shell-common" {
    run_in_zsh 'echo "$SHELL_COMMON"'
    assert_success
    assert_output --partial "${DOTFILES_ROOT}/shell-common"
}

@test "zsh: PATH contains .local/bin" {
    run_in_zsh 'echo "$PATH" | tr ":" "\n" | grep -q ".local/bin" && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: EDITOR is set" {
    run_in_zsh 'test -n "$EDITOR" && echo ok'
    assert_success
    assert_output --partial "ok"
}
