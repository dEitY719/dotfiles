#!/usr/bin/env bats
# tests/bats/functions/help_flag.bats
# -h/--help on argument-taking commands prints help, exits 0 and has no side
# effects (#1880). zsh-theme used to write ZSH_THEME="-h" into ~/.zshrc and
# zsh-snippet used to create ~/.zshrc.d/-h.zsh.

load '../test_helper'

setup() {
    setup_isolated_home
    printf 'ZSH_THEME="robbyrussell"\n' >"$HOME/.zshrc"
    mkdir -p "$HOME/.oh-my-zsh"
}

teardown() {
    teardown_isolated_home
}

@test "zsh-theme / zsh-snippet -h|--help: help only, ~/.zshrc and ~/.zshrc.d untouched (bash + zsh)" {
    local runner flag fn
    for runner in run_in_bash run_in_zsh; do
        for fn in zsh_theme zsh_snippet; do
            for flag in -h --help; do
                "$runner" "$fn $flag"
                assert_success
                assert_output --partial "<name>"
            done
        done
    done
    [ "$(cat "$HOME/.zshrc")" = 'ZSH_THEME="robbyrussell"' ]
    [ ! -e "$HOME/.zshrc.d" ]
}

@test "graphify-setup -h|--help: usage, exit 0, no setup step runs" {
    local flag
    for flag in -h --help; do
        run bash "${SHELL_COMMON}/tools/custom/graphify_setup.sh" "$flag"
        assert_success
        assert_output --partial "graphify-setup"
        refute_output --partial "graphify setup:"
    done
}

@test "./setup.sh -h|--help: usage, exit 0, no step runs" {
    local flag
    for flag in -h --help; do
        run bash "${DOTFILES_ROOT}/setup.sh" "$flag"
        assert_success
        assert_output --partial "--verbose"
        refute_output --partial "dotfiles setup"
    done
}

@test "ghes-mirror -h|--help: help only, no wizard prompt or clone (bash + zsh)" {
    local runner flag
    for runner in run_in_bash run_in_zsh; do
        for flag in -h --help; do
            "$runner" "cd '$HOME' && ghes_mirror $flag </dev/null"
            assert_success
            assert_output --partial "Resulting remotes"
            refute_output --partial "GHES Mirror Wizard"
        done
    done
    [ -z "$(ls -A "$HOME" | grep -v '^\.')" ]
}
