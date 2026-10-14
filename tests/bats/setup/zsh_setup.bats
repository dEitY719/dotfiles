#!/usr/bin/env bats
# tests/bats/setup/zsh_setup.bats
# Issue #2142 — zsh/setup.sh idempotency via run_module_setup (2 runs, 2nd
# run touches nothing under $HOME). Needs a zsh binary (the script's shebang).

load '../test_helper'

teardown() {
    teardown_isolated_home
}

@test "zsh: idempotent, links ~/.zshrc and seeds ~/.zshrc.local" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run_module_setup zsh
    [ "$(readlink "$HOME/.zshrc")" = "${_BATS_REAL_DOTFILES_ROOT}/zsh/zshrc" ]
    [ -f "$HOME/.zshrc.local" ]
}
