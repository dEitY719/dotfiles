#!/usr/bin/env bats
# tests/bats/functions/company_active.bats
# _dotfiles_company_active <plugin-dir> (shell-common/util/setup_mode_read.sh,
# #2251): mode internal AND -e <dir>/company/.git; anything else is inactive.

load '../test_helper'

LIB="${_BATS_REAL_SHELL_COMMON}/util/setup_mode_read.sh"

setup() {
    setup_isolated_home
    unset DOTFILES_SETUP_MODE
    PD="$TEST_TEMP_HOME/plugin"
    mkdir -p "$PD/company"
}

teardown() {
    chmod 644 "$HOME/.dotfiles-setup-mode" 2>/dev/null || true
    teardown_isolated_home
}

_active() {
    run sh -c ". '$LIB'; _dotfiles_company_active \"\$1\"" _ "$1"
}

@test "company_active: internal + .git dir => active" {
    echo internal >"$HOME/.dotfiles-setup-mode"
    mkdir "$PD/company/.git"
    _active "$PD"
    assert_success
}

@test "company_active: internal + .git file (worktree) => active" {
    echo internal >"$HOME/.dotfiles-setup-mode"
    echo "gitdir: /elsewhere" >"$PD/company/.git"
    _active "$PD"
    assert_success
}

@test "company_active: external + .git => inactive" {
    echo external >"$HOME/.dotfiles-setup-mode"
    mkdir "$PD/company/.git"
    _active "$PD"
    assert_failure
}

@test "company_active: internal + no .git (empty company/) => inactive" {
    echo internal >"$HOME/.dotfiles-setup-mode"
    _active "$PD"
    assert_failure
}

@test "company_active: mode file missing => inactive" {
    mkdir "$PD/company/.git"
    _active "$PD"
    assert_failure
}

@test "company_active: mode file unreadable => inactive" {
    [ "$(id -u)" -ne 0 ] || skip "root reads mode-000 files"
    echo internal >"$HOME/.dotfiles-setup-mode"
    chmod 000 "$HOME/.dotfiles-setup-mode"
    mkdir "$PD/company/.git"
    _active "$PD"
    assert_failure
}

@test "company_active: empty plugin-dir => inactive" {
    echo internal >"$HOME/.dotfiles-setup-mode"
    _active ""
    assert_failure
}
