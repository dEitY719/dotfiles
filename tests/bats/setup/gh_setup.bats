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

# Issue #2428 — internal mode guides a one-time --insecure-storage login for
# each host whose hosts.yml block holds no plaintext oauth_token.
@test "gh: internal without plaintext tokens guides --insecure-storage login per host" {
    setup_isolated_home
    export DOTFILES_GHES_HOST=ghes.example.test
    run_module_setup gh internal
    [[ "$output" == *"gh auth login -h ghes.example.test --insecure-storage"* ]]
    [[ "$output" == *"gh auth login -h github.com --insecure-storage"* ]]
}

@test "gh: internal with plaintext tokens prints no login guide nor token" {
    setup_isolated_home
    export DOTFILES_GHES_HOST=ghes.example.test
    mkdir -p "$HOME/.config/gh"
    cat >"$HOME/.config/gh/hosts.yml" <<'YML'
ghes.example.test:
    users:
        me:
            oauth_token: gho_fake1
    user: me
github.com:
    oauth_token: gho_fake2
    user: me
YML
    run_module_setup gh internal
    [[ "$output" != *"--insecure-storage"* ]]
    [[ "$output" != *"gho_fake"* ]]
}

@test "gh: internal guides only the host whose token is missing" {
    setup_isolated_home
    export DOTFILES_GHES_HOST=ghes.example.test
    mkdir -p "$HOME/.config/gh"
    cat >"$HOME/.config/gh/hosts.yml" <<'YML'
ghes.example.test:
    oauth_token:
    user: me
github.com:
    oauth_token: gho_fake2
YML
    run_module_setup gh internal
    [[ "$output" == *"gh auth login -h ghes.example.test --insecure-storage"* ]]
    [[ "$output" != *"gh auth login -h github.com"* ]]
}

@test "gh: public mode never prints the keyring login guide" {
    run_module_setup gh public
    [[ "$output" != *"--insecure-storage"* ]]
}

@test "gh: external mode never prints the keyring login guide" {
    run_module_setup gh external
    [[ "$output" != *"--insecure-storage"* ]]
}
