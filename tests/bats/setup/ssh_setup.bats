#!/usr/bin/env bats
# tests/bats/setup/ssh_setup.bats
# Issue #2142 — ssh/setup.sh idempotency via run_module_setup (2 runs, 2nd
# run touches nothing under $HOME).

load '../test_helper'

teardown() {
    teardown_isolated_home
}

@test "ssh: idempotent, a 700 ~/.ssh; the ~/.ssh/config link is symlinks.conf's (#2139)" {
    run_module_setup ssh
    [ "$(stat -c %a "$HOME/.ssh")" = 700 ]
    [ "$(stat -c %a "${_BATS_REAL_DOTFILES_ROOT}/ssh/config")" = 600 ]
    [ ! -e "$HOME/.ssh/config" ]
}
