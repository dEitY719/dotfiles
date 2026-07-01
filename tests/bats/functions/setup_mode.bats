#!/usr/bin/env bats
# tests/bats/functions/setup_mode.bats
# Coverage for shell-common/util/setup_mode.sh's `_apply_setup_mode_config`.
#
# Issue #1051: the proxy-cleanup `case` only matched the legacy numeric
# mode values (1/2/3). Since #703, shell-common/setup.sh writes the
# string values (`internal`/`external`/`public`) to
# ~/.dotfiles-setup-mode, so `external`/`public` PCs silently kept any
# WSL2-inherited proxy env vars. gh_host.sh (#703) already migrated to
# dual string/numeric support; this file was the one left behind.

load '../test_helper'

setup() {
    setup_isolated_home
    export http_proxy="http://127.0.0.1:8080"
    export https_proxy="http://127.0.0.1:8080"
}

teardown() {
    teardown_isolated_home
}

@test "mode=external clears proxy vars" {
    echo "external" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[]"
}

@test "mode=public clears proxy vars" {
    echo "public" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[]"
}

@test "mode=internal leaves proxy vars untouched" {
    echo "internal" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[http://127.0.0.1:8080]"
}

@test "legacy mode=1 (public) clears proxy vars" {
    echo "1" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[]"
}

@test "legacy mode=3 (external) clears proxy vars" {
    echo "3" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[]"
}

@test "legacy mode=2 (internal) leaves proxy vars untouched" {
    echo "2" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[http://127.0.0.1:8080]"
}

@test "missing setup-mode file leaves proxy vars untouched" {
    rm -f "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[http://127.0.0.1:8080]"
}

@test "zsh: mode=external clears proxy vars" {
    echo "external" > "$HOME/.dotfiles-setup-mode"
    run_in_zsh '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[]"
}
