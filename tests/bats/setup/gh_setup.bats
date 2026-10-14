#!/usr/bin/env bats
# tests/bats/setup/gh_setup.bats
# Issue #2142 — gh/setup.sh idempotency via run_module_setup (2 runs, 2nd
# run touches nothing under $HOME).

load '../test_helper'

teardown() {
    teardown_isolated_home
}

@test "gh: idempotent, links ~/.config/gh/config.yml" {
    run_module_setup gh
    [ "$(readlink "$HOME/.config/gh/config.yml")" = "${_BATS_REAL_DOTFILES_ROOT}/gh/config.yml" ]
}
