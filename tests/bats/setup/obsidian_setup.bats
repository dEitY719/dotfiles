#!/usr/bin/env bats
# tests/bats/setup/obsidian_setup.bats
# Issue #2142 — obsidian/setup.sh idempotency via run_module_setup (2 runs, 2nd
# run touches nothing under $HOME).

load '../test_helper'

teardown() {
    teardown_isolated_home
}

@test "obsidian: idempotent, links ~/.local/bin/obsidian" {
    run_module_setup obsidian
    [ "$(readlink "$HOME/.local/bin/obsidian")" = "${_BATS_REAL_DOTFILES_ROOT}/obsidian/bin/obsidian" ]
}
