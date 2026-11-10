#!/usr/bin/env bats

load '../test_helper'

teardown() {
    teardown_isolated_home
}

@test "isolated home clears inherited setup mode and GHES host" {
    export DOTFILES_SETUP_MODE=internal DOTFILES_GHES_HOST=leak.example.invalid
    setup_isolated_home
    [ "${DOTFILES_SETUP_MODE+x}" != x ]
    [ "${DOTFILES_GHES_HOST+x}" != x ]
}
