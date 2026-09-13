#!/usr/bin/env bats
# tests/bats/tools/install_opencode.bats
# install_opencode.sh install-path routing and post-install verification.
#
# Background: npm 12 blocks dependency install scripts by default
# (allow-scripts), so `npm install -g opencode-ai` silently skipped the
# postinstall that swaps bin/opencode.exe for the real binary. The installer
# still reported success while `opencode` was a placeholder that exits 1.
# Fix: public/external use the official curl installer (~/.opencode/bin),
# internal keeps npm (opencode.ai is blocked there) with an explicit
# --allow-scripts, and both paths verify `opencode --version` actually runs.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
INSTALL_OPENCODE_SCRIPT="${TOOLS_DIR}/install_opencode.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

run_opencode_tool() {
    run_sourced_tool_script "$TOOLS_DIR" "$INSTALL_OPENCODE_SCRIPT" "$1"
}

# --- install method routing --------------------------------------------------

@test "opencode_install_method: internal routes to npm" {
    run_opencode_tool 'opencode_install_method internal'
    assert_success
    assert_output "npm"
}

@test "opencode_install_method: home and external route to curl" {
    run_opencode_tool '
        opencode_install_method home
        opencode_install_method external
    '
    assert_success
    assert_output "curl
curl"
}

# --- npm path ------------------------------------------------------------------

@test "install_opencode_via_npm: allows opencode-ai install scripts explicitly" {
    run_opencode_tool '
        npm() { printf "%s\n" "$*"; }
        install_opencode_via_npm
    '
    assert_success
    assert_output --partial "--allow-scripts=opencode-ai"
    assert_output --partial "opencode-ai"
}

# --- curl path -----------------------------------------------------------------

@test "install_opencode_via_curl: runs the official installer with --no-modify-path" {
    run_opencode_tool '
        curl() {
            out=""
            while [ $# -gt 0 ]; do
                [ "$1" = "-o" ] && out="$2"
                shift
            done
            printf "%s\n" "printf \"installer-args:%s\\n\" \"\$*\"" > "$out"
        }
        install_opencode_via_curl
    '
    assert_success
    assert_output --partial "installer-args:--no-modify-path"
}

@test "install_opencode_via_curl: download failure fails without running an installer" {
    run_opencode_tool '
        curl() { return 22; }
        install_opencode_via_curl
    '
    assert_failure
    refute_output --partial "installer-args"
}

@test "opencode_binary_path: curl installs land in ~/.opencode/bin" {
    run_opencode_tool 'opencode_binary_path curl'
    assert_success
    assert_output "$HOME/.opencode/bin/opencode"
}

# --- verification --------------------------------------------------------------

@test "verify_opencode_binary: rejects the npm postinstall placeholder" {
    local bin="$HOME/placeholder/opencode"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' \
        "echo \"Error: opencode-ai's postinstall script was not run.\" >&2" \
        'exit 1' > "$bin"
    chmod +x "$bin"

    run_opencode_tool "verify_opencode_binary '$bin'"
    assert_failure
}

@test "verify_opencode_binary: rejects a missing binary" {
    run_opencode_tool "verify_opencode_binary '$HOME/nope/opencode'"
    assert_failure
}

@test "verify_opencode_binary: accepts a binary whose --version succeeds" {
    local bin="$HOME/good/opencode"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo 1.18.30' > "$bin"
    chmod +x "$bin"

    run_opencode_tool "verify_opencode_binary '$bin'"
    assert_success
    assert_output "1.18.30"
}

# --- structural guard: main() consumes the helpers -----------------------------

@test "main routes through opencode_install_method and verify_opencode_binary" {
    run grep -c 'opencode_install_method "\$environment"' "$INSTALL_OPENCODE_SCRIPT"
    assert_success
    run grep -c 'verify_opencode_binary' "$INSTALL_OPENCODE_SCRIPT"
    assert_success
    run grep -c 'npm install -g opencode-ai 2>' "$INSTALL_OPENCODE_SCRIPT"
    assert_failure
}
