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

@test "opencode_install_method: public, external and legacy home route to curl" {
    run_opencode_tool '
        opencode_install_method public
        opencode_install_method external
        opencode_install_method home
    '
    assert_success
    assert_output "curl
curl
curl"
}

# --- environment selection (F4) -----------------------------------------------
# Same numbering/value names as ./setup.sh (1=public 2=internal 3=external);
# Enter keeps the current setup mode read via util/setup_mode_read.sh.
# ux_* are stubbed: DOTFILES_TEST_MODE makes init.sh skip ux_lib.

_select_env() {
    run_opencode_tool "
        ux_section() { printf '%s\n' \"\$*\"; }
        ux_bullet() { printf '%s\n' \"\$*\"; }
        ux_error() { printf '%s\n' \"\$*\" >&2; }
        ux_input() { printf '%s\n' \"\$1\" >&2; read -r r; printf '%s\n' \"\$r\"; }
        printf '%s\n' '$1' | opencode_select_environment 2>'$HOME/menu'
    "
}

@test "opencode_select_environment: 2 is internal and 3 is external (setup.sh order)" {
    rm -f "$HOME/.dotfiles-setup-mode"
    _select_env 2
    assert_success
    assert_output "internal"
    _select_env 3
    assert_output "external"
    _select_env 1
    assert_output "public"
}

@test "opencode_select_environment: Enter keeps the current setup mode (CRLF, legacy numeric)" {
    printf '2\r\n' >"$HOME/.dotfiles-setup-mode"
    _select_env ""
    assert_success
    assert_output "internal"
    run cat "$HOME/menu"
    assert_output --partial "Enter=current: internal"
}

@test "opencode_select_environment: menu has public/internal/external and no emoji" {
    printf 'external\n' >"$HOME/.dotfiles-setup-mode"
    _select_env ""
    assert_output "external"
    run cat "$HOME/menu"
    assert_output --partial "1) Public PC"
    assert_output --partial "2) Internal company PC"
    assert_output --partial "3) External company PC (VPN)"
    refute_output --partial "Home"
    run bash -c "LC_ALL=C grep -c '[^[:print:][:space:]]' '$HOME/menu'"
    assert_output "0"
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

@test "opencode_binary_path: npm installs land under npm prefix -g" {
    run_opencode_tool '
        npm() { echo /fake/npm-prefix; }
        opencode_binary_path npm
    '
    assert_success
    assert_output "/fake/npm-prefix/bin/opencode"
}

# Swallowing npm's stderr left only the misleading "/bin/opencode" path behind.
@test "opencode_binary_path: a failing npm prefix -g surfaces npm's own error" {
    run_opencode_tool '
        npm() { echo "npm ERR! cannot determine prefix" >&2; return 1; }
        opencode_binary_path npm
    '
    assert_failure
    assert_output --partial "npm ERR! cannot determine prefix"
    refute_output --partial "/bin/opencode"
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

# --- internal config (#1967) ----------------------------------------------------

@test "generate_internal_config: delegates to setup.sh and writes the config" {
    run_opencode_tool 'ux_info() { :; }; generate_internal_config'
    assert_success
    assert_output --partial "Setting up OpenCode configuration for: internal"
    [ -f "$HOME/.config/opencode/opencode.json" ]
}
