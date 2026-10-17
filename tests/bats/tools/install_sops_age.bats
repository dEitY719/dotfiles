#!/usr/bin/env bats
# tests/bats/tools/install_sops_age.bats
# install_sops_age.sh: mise shims PATH hint (#2234).

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
INSTALL_SOPS_AGE_SCRIPT="${TOOLS_DIR}/install_sops_age.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

run_sops_tool() {
    run_sourced_tool_script "$TOOLS_DIR" "$INSTALL_SOPS_AGE_SCRIPT" "$1"
}

@test "sops_age_shims_hint: prints export when sops/age are not on PATH" {
    run_sops_tool '
        PATH=/usr/bin:/bin
        unset MISE_DATA_DIR XDG_DATA_HOME
        sops_age_installed() { return 1; }
        sops_age_shims_hint
    '
    assert_success
    assert_output --partial "export PATH=\"${HOME}/.local/share/mise/shims:\$PATH\""
}

@test "sops_age_shims_hint: silent when sops/age already on PATH" {
    run_sops_tool '
        sops_age_installed() { return 0; }
        sops_age_shims_hint
    '
    assert_success
    assert_output ""
}

@test "sops_age_shims_hint: silent when shims dir is already on PATH" {
    run_sops_tool '
        unset MISE_DATA_DIR XDG_DATA_HOME
        PATH="$HOME/.local/share/mise/shims:/usr/bin:/bin"
        sops_age_installed() { return 1; }
        sops_age_shims_hint
    '
    assert_success
    assert_output ""
}

@test "main: mise install path prints the shims hint, release path does not" {
    mkdir -p "$HOME/stub"
    printf '#!/bin/sh\nexit 0\n' > "$HOME/stub/mise"
    chmod +x "$HOME/stub/mise"
    run_sops_tool '
        sops_age_installed() { return 1; }
        PATH="$HOME/stub:/usr/bin:/bin"
        unset MISE_DATA_DIR XDG_DATA_HOME
        main
    '
    assert_success
    assert_output --partial "mise/shims"

    run_sops_tool '
        sops_age_installed() { return 1; }
        command() { [ "$1" = "-v" ] && [ "$2" = mise ] && return 1; builtin command "$@"; }
        install_sops_age_via_release() { return 0; }
        main
    '
    assert_success
    refute_output --partial "mise/shims"
}
