#!/bin/sh
# shellcheck shell=bash
# shell-common/tools/custom/lib/codex_standalone.sh
# Shared core for codex-install / codex-update (issue #2426): install-method
# detection, the official standalone installer run, post-install verification
# and the npm -> standalone migration step.
#
# Sourced by ../install_codex.sh and ../update_codex.sh after init.sh and
# install_helpers.sh (verify_installed_binary). bash only: it relies on
# `type -P`. codex_status (integrations/codex.sh) runs the detection through
# `bash -c` so both interactive shells share this one SSOT.
#
# Official installer contract (https://chatgpt.com/codex/install.sh):
# `--release VER`, CODEX_NON_INTERACTIVE, CODEX_INSTALL_DIR, CODEX_HOME.

CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"
CODEX_NPM_PACKAGE="@openai/codex"

_codex_bin_dir() {
    printf '%s\n' "${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
}

_codex_standalone_root() {
    printf '%s\n' "${CODEX_HOME:-$HOME/.codex}/packages/standalone"
}

# Resolve a path through symlinks; plain readlink output is enough to spot a
# node_modules target when readlink -f is unavailable.
_codex_resolve_path() {
    readlink -f "$1" 2>/dev/null || readlink "$1" 2>/dev/null || printf '%s\n' "$1"
}

# _codex_classify_bin <path> -> standalone | npm | other
# standalone: an installer link into $CODEX_HOME/packages/standalone/current/,
# or any path that resolves under the standalone root (relative links and a
# symlinked CODEX_HOME included). npm: resolves into node_modules/@openai/codex.
_codex_classify_bin() {
    local bin="$1" root real_root target resolved
    root="$(_codex_standalone_root)"
    if [ -L "$bin" ]; then
        target="$(readlink "$bin" 2>/dev/null || true)"
        case "$target" in "$root/current/"*) printf 'standalone\n'; return 0 ;; esac
    fi
    resolved="$(_codex_resolve_path "$bin")"
    real_root="$(cd -P "$root" 2>/dev/null && pwd)" || real_root="$root"
    case "$resolved" in
        "$root/"* | "$real_root/"*) printf 'standalone\n' ;;
        */node_modules/"$CODEX_NPM_PACKAGE"/*) printf 'npm\n' ;;
        *) printf 'other\n' ;;
    esac
}

# _codex_detect_install [--no-npm]
# Sets CODEX_INSTALL_METHOD (standalone | npm | none | other),
# CODEX_EXISTING_BIN (the codex found on PATH, if any), CODEX_NPM_PRESENT (1
# when the global npm package exists, even next to standalone) and
# CODEX_NPM_ROOT. Precedence: a standalone install in BIN_DIR, then the codex
# that PATH actually runs (so an active Homebrew/Bun/manual binary is never
# "migrated" because an unused npm package also exists), then a global npm
# package with no codex on PATH. --no-npm never runs npm (dry-run,
# codex_status): npm is then recognised only from the codex on PATH.
_codex_detect_install() {
    local query_npm=1 bin_dir
    [ "${1:-}" = "--no-npm" ] && query_npm=0
    bin_dir="$(_codex_bin_dir)"
    CODEX_INSTALL_METHOD=none
    CODEX_NPM_PRESENT=0
    CODEX_NPM_ROOT=""
    CODEX_EXISTING_BIN="$(PATH="$bin_dir:$PATH" type -P codex 2>/dev/null || true)"
    if [ "$query_npm" = 1 ] && command -v npm >/dev/null 2>&1; then
        CODEX_NPM_ROOT="$(npm root -g 2>/dev/null || true)"
        if [ -n "$CODEX_NPM_ROOT" ] && [ -d "$CODEX_NPM_ROOT/$CODEX_NPM_PACKAGE" ]; then
            CODEX_NPM_PRESENT=1
        fi
    fi

    if [ -L "$bin_dir/codex" ] && [ "$(_codex_classify_bin "$bin_dir/codex")" = standalone ]; then
        CODEX_INSTALL_METHOD=standalone
    elif [ -n "$CODEX_EXISTING_BIN" ]; then
        CODEX_INSTALL_METHOD="$(_codex_classify_bin "$CODEX_EXISTING_BIN")"
    elif [ "$CODEX_NPM_PRESENT" = 1 ]; then
        CODEX_INSTALL_METHOD=npm
    fi
    return 0
}

# _codex_install_method [--no-npm] -> prints standalone | npm | none | other
_codex_install_method() {
    _codex_detect_install "$@"
    printf '%s\n' "$CODEX_INSTALL_METHOD"
}

_codex_cleanup_installer() {
    [ -z "${CODEX_INSTALLER_FILE:-}" ] || rm -f "$CODEX_INSTALLER_FILE"
    CODEX_INSTALLER_FILE=""
}

# _codex_fetch_installer -- download the official installer to a temp file
# (never `curl | sh`, #1801) into CODEX_INSTALLER_FILE. The file is removed on
# exit and on Ctrl-C / SIGTERM as well as after the run.
_codex_fetch_installer() {
    CODEX_INSTALLER_FILE="$(mktemp)" || {
        CODEX_INSTALLER_FILE=""
        ux_error "Cannot create a temp file for the installer."
        return 1
    }
    trap _codex_cleanup_installer EXIT
    trap '_codex_cleanup_installer; exit 130' INT TERM
    if ! curl -fsSL "$CODEX_INSTALLER_URL" -o "$CODEX_INSTALLER_FILE"; then
        _codex_cleanup_installer
        ux_error "Failed to download the official Codex installer."
        return 1
    fi
}

# _codex_run_installer [installer-args...]   (e.g. --release 0.170.0)
# Run the fetched installer with BIN_DIR prepended to PATH (so upstream does
# not edit symlinked rc files, #1802) and CODEX_NON_INTERACTIVE=1 (conflicts
# are handled here, never by an upstream prompt), then verify the installed
# binary itself. Sets CODEX_INSTALLED_VERSION on success; installer and verify
# failures print their own error and return 1.
_codex_run_installer() {
    local bin_dir codex_bin rc=0
    bin_dir="$(_codex_bin_dir)"
    codex_bin="$bin_dir/codex"
    CODEX_INSTALLED_VERSION=""
    PATH="$bin_dir:$PATH" CODEX_NON_INTERACTIVE=1 sh "$CODEX_INSTALLER_FILE" "$@" || rc=$?
    _codex_cleanup_installer
    if [ "$rc" -ne 0 ]; then
        ux_error "The official Codex installer failed (exit $rc)."
        return 1
    fi
    if ! CODEX_INSTALLED_VERSION="$(verify_installed_binary "$codex_bin" 2>&1)"; then
        ux_error "Codex CLI binary is not runnable after install: $codex_bin ($CODEX_INSTALLED_VERSION)"
        return 1
    fi
}

# _codex_standalone_install [installer-args...] -- fetch, run, verify.
_codex_standalone_install() {
    _codex_fetch_installer && _codex_run_installer "$@"
}

# _codex_npm_root_writable -- 0 unless the detected npm global root exists and
# is not writable (root-owned prefix: npm uninstall would need sudo).
_codex_npm_root_writable() {
    [ -z "$CODEX_NPM_ROOT" ] || [ -w "$CODEX_NPM_ROOT" ]
}

# _codex_migrate_from_npm -- remove the global npm package (one call). On
# failure nothing else is attempted and the manual command is printed.
_codex_migrate_from_npm() {
    ux_info "Remove npm package: npm uninstall -g $CODEX_NPM_PACKAGE"
    if ! npm uninstall -g "$CODEX_NPM_PACKAGE"; then
        ux_error "Failed to uninstall the npm package; standalone install was not attempted."
        ux_info "Remove it manually (prefix with sudo if the npm root is root-owned):"
        ux_bullet "npm uninstall -g $CODEX_NPM_PACKAGE"
        return 1
    fi
    hash -r
    return 0
}

# _codex_warn_path_shadow -- warn when the shell would not run the standalone
# binary (e.g. ~/.npm-global/bin ahead of ~/.local/bin with a stale copy).
_codex_warn_path_shadow() {
    local bin_dir resolved
    bin_dir="$(_codex_bin_dir)"
    hash -r
    resolved="$(type -P codex 2>/dev/null || true)"
    if [ -z "$resolved" ]; then
        ux_warning "$bin_dir is not on PATH; add it to run codex."
    elif [ "$resolved" != "$bin_dir/codex" ]; then
        ux_warning "Another Codex executable comes first on PATH: $resolved"
        ux_info "Remove it with its package manager or put $bin_dir earlier in PATH."
    fi
}
