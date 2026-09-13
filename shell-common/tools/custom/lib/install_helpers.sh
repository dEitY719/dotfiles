#!/bin/sh
# shell-common/tools/custom/lib/install_helpers.sh
# Remote-installer and post-install verification helpers for install*.sh
# (issue #1801). Sourced by ../install*.sh.
#
# Pure functions with no ux_* output: init.sh returns before defining ux_*
# under DOTFILES_TEST_MODE=1, and these must stay defined for bats.

# run_remote_installer <url> [installer-args...]
# Download to a temp file first: `curl | sh` reports success on a failed
# download because the shell just reads empty input. Env for the installer is
# passed as a call prefix (UV_NO_MODIFY_PATH=1 run_remote_installer ...).
# bash, not sh: claude's install.sh uses [[ =~ ]]; the POSIX ones run too.
run_remote_installer() {
    local url="$1" installer rc=0
    shift
    installer=$(mktemp) || return 1
    if ! curl -fsSL "$url" -o "$installer"; then
        rm -f "$installer"
        return 1
    fi
    bash "$installer" "$@" || rc=$?
    rm -f "$installer"
    return "$rc"
}

# verify_installed_binary <path> [args...]   (default args: --version)
# Succeeds (printing the output) only if the binary actually runs. Takes the
# install location, not `command -v`, so an older copy earlier in PATH can't
# pass for the one just installed.
verify_installed_binary() {
    local bin="$1"
    shift
    if [ -z "$bin" ] || [ ! -x "$bin" ]; then
        return 1
    fi
    [ $# -gt 0 ] || set -- --version
    "$bin" "$@"
}
