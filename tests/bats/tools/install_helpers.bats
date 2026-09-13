#!/usr/bin/env bats
# tests/bats/tools/install_helpers.bats
# lib/install_helpers.sh: download-then-run remote installers and verify the
# installed binary actually runs (issue #1801).
#
# Background: `curl | sh` and `sh -c "$(curl ...)"` report success when the
# download fails (the shell reads empty input and exits 0), and the old
# post-install checks only warned when `--version` failed. Installers then
# printed "Setup Complete" for a tool that was never installed.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
HELPERS="${TOOLS_DIR}/lib/install_helpers.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# Run BODY in bash with the helpers sourced. TMPDIR is pinned inside the
# isolated HOME so the temp-file cleanup can be asserted.
run_helpers() {
    mkdir -p "$HOME/tmp"
    run bash -c "
        export HOME='${HOME}' TMPDIR='${HOME}/tmp'
        . '${HELPERS}' || exit 99
        $1
    "
}

# curl double: writes INSTALLER_BODY to the -o target.
CURL_OK='
    curl() {
        out=""
        while [ $# -gt 0 ]; do
            [ "$1" = "-o" ] && out="$2"
            shift
        done
        printf "%s\n" "$INSTALLER_BODY" > "$out"
    }
'

# --- run_remote_installer ------------------------------------------------------

@test "run_remote_installer: download failure fails without running an installer" {
    run_helpers '
        curl() { return 22; }
        bash() { echo installer-ran; }
        run_remote_installer https://example.invalid/install.sh
    '
    assert_failure
    refute_output --partial "installer-ran"
}

@test "run_remote_installer: passes installer args through" {
    run_helpers "
        $CURL_OK
        INSTALLER_BODY='printf \"args:%s\\n\" \"\$*\"'
        run_remote_installer https://example.invalid/install.sh --keep-zshrc
    "
    assert_success
    assert_output "args:--keep-zshrc"
}

@test "run_remote_installer: env prefix is inherited by the installer" {
    run_helpers "
        $CURL_OK
        INSTALLER_BODY='printf \"env:%s\\n\" \"\${UV_NO_MODIFY_PATH-unset}\"'
        UV_NO_MODIFY_PATH=1 run_remote_installer https://example.invalid/install.sh
    "
    assert_success
    assert_output "env:1"
}

@test "run_remote_installer: propagates installer exit code and removes the temp file" {
    run_helpers "
        $CURL_OK
        INSTALLER_BODY='exit 3'
        rc=0
        run_remote_installer https://example.invalid/install.sh || rc=\$?
        echo \"rc=\$rc\"
        ls -A \"\$TMPDIR\" | wc -l
    "
    assert_success
    assert_output "rc=3
0"
}

# --- verify_installed_binary ---------------------------------------------------

@test "verify_installed_binary: rejects an empty path and a missing binary" {
    run_helpers "verify_installed_binary ''"
    assert_failure
    run_helpers "verify_installed_binary '$HOME/nope/tool'"
    assert_failure
}

@test "verify_installed_binary: rejects a non-executable file" {
    local bin="$HOME/noexec/tool"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo 1.0' > "$bin"

    run_helpers "verify_installed_binary '$bin'"
    assert_failure
}

@test "verify_installed_binary: rejects a placeholder that exits 1" {
    local bin="$HOME/placeholder/tool"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo "postinstall not run" >&2' 'exit 1' > "$bin"
    chmod +x "$bin"

    run_helpers "verify_installed_binary '$bin'"
    assert_failure
}

@test "verify_installed_binary: runs --version by default and prints it" {
    local bin="$HOME/good/tool"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo "tool $*"' > "$bin"
    chmod +x "$bin"

    run_helpers "verify_installed_binary '$bin'"
    assert_success
    assert_output "tool --version"
}

@test "verify_installed_binary: custom args replace --version" {
    local bin="$HOME/good/tool"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo "tool $*"' > "$bin"
    chmod +x "$bin"

    run_helpers "verify_installed_binary '$bin' version --short"
    assert_success
    assert_output "tool version --short"
}

# --- static regression guard ---------------------------------------------------

@test "no install*.sh pipes curl into a shell or runs sh -c \"\$(curl ...)\"" {
    local pattern='curl[^#]*\|[[:space:]]*(ba)?sh\b|sh -c "\$\(curl'
    run bash -c 'grep -nE "$1" "$2"/install*.sh | grep -vE "^[^:]+:[0-9]+:[[:space:]]*#"' \
        _ "$pattern" "$TOOLS_DIR"
    assert_output ""
}
