#!/usr/bin/env bats
# tests/bats/tools/install_herdr.bats
# install_herdr.sh install-path routing and download-failure handling.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
INSTALL_HERDR_SCRIPT="${TOOLS_DIR}/install_herdr.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

run_herdr_tool() {
    run_sourced_tool_script "$TOOLS_DIR" "$INSTALL_HERDR_SCRIPT" "$1"
}

@test "herdr_install_method: internal routes to release, others to installer" {
    run_herdr_tool '
        herdr_install_method internal
        herdr_install_method public
        herdr_install_method external
    '
    assert_success
    assert_output "release
installer
installer"
}

@test "herdr_release_url: latest by default, pinned tag with HERDR_VERSION" {
    run_herdr_tool '
        herdr_release_url
        HERDR_VERSION=v0.9.0 herdr_release_url
    '
    assert_success
    assert_output "https://github.com/ogulcancelik/herdr/releases/latest/download/herdr-linux-x86_64
https://github.com/ogulcancelik/herdr/releases/download/v0.9.0/herdr-linux-x86_64"
}

@test "install_herdr_via_installer: download failure fails without running an installer" {
    run_herdr_tool '
        curl() { return 22; }
        sh() { echo "installer-ran"; }
        install_herdr_via_installer
    '
    assert_failure
    refute_output --partial "installer-ran"
}

@test "install_herdr_via_release: installs the downloaded binary executable" {
    run_herdr_tool '
        uname() { [ "$1" = "-s" ] && echo Linux || echo x86_64; }
        curl() {
            while [ $# -gt 0 ]; do [ "$1" = "-o" ] && printf "bin" > "$2"; shift; done
        }
        install_herdr_via_release && [ -x "$HOME/.local/bin/herdr" ] && echo ok
    '
    assert_success
    assert_output "ok"
}
