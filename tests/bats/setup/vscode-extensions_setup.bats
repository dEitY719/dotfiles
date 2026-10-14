#!/usr/bin/env bats
# tests/bats/setup/vscode-extensions_setup.bats
# Issue #2142 — vscode-extensions/setup.sh idempotency via run_module_setup (2 runs, 2nd
# run touches nothing under $HOME).

load '../test_helper'

teardown() {
    teardown_isolated_home
}

@test "vscode-extensions: idempotent, links ~/.prettierrc" {
    run_module_setup vscode-extensions
    [ "$(readlink "$HOME/.prettierrc")" = "${_BATS_REAL_DOTFILES_ROOT}/vscode-extensions/.prettierrc" ]
}
