#!/usr/bin/env bats
# tests/bats/setup/ssh_setup.bats
# Issue #2142 — ssh/setup.sh idempotency via run_module_setup (2 runs, 2nd
# run touches nothing under $HOME).

load '../test_helper'

teardown() {
    teardown_isolated_home
}

@test "ssh: idempotent, links ~/.ssh/config with a 700 ~/.ssh" {
    run_module_setup ssh
    [ "$(readlink "$HOME/.ssh/config")" = "${_BATS_REAL_DOTFILES_ROOT}/ssh/config" ]
    [ "$(stat -c %a "$HOME/.ssh")" = 700 ]
}
