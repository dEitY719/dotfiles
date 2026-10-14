#!/usr/bin/env bats
# tests/bats/setup/obsidian_setup.bats
# Issue #2142 — obsidian/setup.sh idempotency via run_module_setup (2 runs, 2nd
# run touches nothing under $HOME).

load '../test_helper'

teardown() {
    teardown_isolated_home
}

@test "obsidian: idempotent, keeps the wrapper executable; the link is symlinks.conf's (#2139)" {
    run_module_setup obsidian
    [ -x "${_BATS_REAL_DOTFILES_ROOT}/obsidian/bin/obsidian" ]
    [ ! -e "$HOME/.local/bin/obsidian" ]
}
