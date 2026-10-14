#!/usr/bin/env bats
# tests/bats/lib_setup/mode.bats
# Precedence of shell-common/lib/setup/mode.sh dotfiles_setup_mode_resolve
# (#2137): DOTFILES_SETUP_MODE env > --mode arg > ~/.dotfiles-setup-mode.

load '../test_helper'

MODE_LIB="${_BATS_REAL_SHELL_COMMON}/lib/setup/mode.sh"

setup() {
    setup_isolated_home
    unset DOTFILES_SETUP_MODE
}

teardown() {
    teardown_isolated_home
}

_resolve() {
    run sh -c ". '$MODE_LIB'; dotfiles_setup_mode_resolve $*"
}

@test "mode: file only" {
    printf 'internal\r\n' >"$HOME/.dotfiles-setup-mode"
    _resolve
    assert_success
    assert_output "internal"
}

@test "mode: --mode beats the file" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    _resolve --mode external
    assert_output "external"
    _resolve --mode=3
    assert_output "external"
}

@test "mode: env beats --mode and the file" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    DOTFILES_SETUP_MODE=1 _resolve --mode external
    assert_output "public"
}

@test "mode: nothing set prints empty" {
    _resolve
    assert_success
    assert_output ""
}

@test "mode: an invalid value fails" {
    DOTFILES_SETUP_MODE=bogus _resolve
    assert_failure
    _resolve --mode bogus
    assert_failure
}

@test "mode: _dotfiles_setup_mode itself prefers the env" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    DOTFILES_SETUP_MODE=external run sh -c ". '${_BATS_REAL_SHELL_COMMON}/util/setup_mode_read.sh'; _dotfiles_setup_mode"
    assert_output "external"
}
