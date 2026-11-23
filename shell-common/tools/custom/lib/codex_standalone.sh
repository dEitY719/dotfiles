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

# _codex_detect_install [--no-npm]
# Sets CODEX_INSTALL_METHOD (standalone | npm | none | other),
# CODEX_EXISTING_BIN (the codex found on PATH, if any) and CODEX_NPM_PRESENT
# (1 when the global npm package exists, even next to standalone). --no-npm never runs
# npm (dry-run, codex_status): npm is then recognised only by a codex on PATH
# that resolves into node_modules/@openai/codex.
_codex_detect_install() {
    local query_npm=1 bin_dir standalone_root link target npm_root resolved
    [ "${1:-}" = "--no-npm" ] && query_npm=0
    bin_dir="$(_codex_bin_dir)"
    standalone_root="$(_codex_standalone_root)"
    CODEX_INSTALL_METHOD=none
    CODEX_NPM_PRESENT=0
    CODEX_EXISTING_BIN="$(PATH="$bin_dir:$PATH" type -P codex 2>/dev/null || true)"
    if [ "$query_npm" = 1 ] && command -v npm >/dev/null 2>&1; then
        npm_root="$(npm root -g 2>/dev/null || true)"
        if [ -n "$npm_root" ] && [ -d "$npm_root/$CODEX_NPM_PACKAGE" ]; then
            CODEX_NPM_PRESENT=1
        fi
    fi

    link="$bin_dir/codex"
    if [ -L "$link" ]; then
        target="$(readlink "$link" 2>/dev/null || true)"
        case "$target" in
            "$standalone_root/current/"*) CODEX_INSTALL_METHOD=standalone; return 0 ;;
        esac
    fi
    if [ "$CODEX_NPM_PRESENT" = 1 ]; then
        CODEX_INSTALL_METHOD=npm
        return 0
    fi
    if [ -n "$CODEX_EXISTING_BIN" ]; then
        resolved="$(_codex_resolve_path "$CODEX_EXISTING_BIN")"
        case "$resolved" in
            */node_modules/"$CODEX_NPM_PACKAGE"/*) CODEX_INSTALL_METHOD=npm ;;
            *) CODEX_INSTALL_METHOD=other ;;
        esac
    fi
    return 0
}

# _codex_install_method [--no-npm] -> prints standalone | npm | none | other
_codex_install_method() {
    _codex_detect_install "$@"
    printf '%s\n' "$CODEX_INSTALL_METHOD"
}

# _codex_standalone_install [installer-args...]   (e.g. --release 0.170.0)
# Download the official installer to a temp file (never `curl | sh`, #1801),
# run it with BIN_DIR prepended to PATH (so upstream does not edit symlinked
# rc files, #1802) and CODEX_NON_INTERACTIVE=1 (conflicts are handled here,
# never by an upstream prompt), then verify the installed binary itself.
# Sets CODEX_INSTALLED_VERSION on success; each failing stage (download,
# installer, verify) prints its own error and returns 1.
_codex_standalone_install() {
    local bin_dir codex_bin installer rc=0
    bin_dir="$(_codex_bin_dir)"
    codex_bin="$bin_dir/codex"
    CODEX_INSTALLED_VERSION=""
    installer="$(mktemp)" || { ux_error "Cannot create a temp file for the installer."; return 1; }
    if ! curl -fsSL "$CODEX_INSTALLER_URL" -o "$installer"; then
        rm -f "$installer"
        ux_error "Failed to download the official Codex installer."
        return 1
    fi
    PATH="$bin_dir:$PATH" CODEX_NON_INTERACTIVE=1 sh "$installer" "$@" || rc=$?
    rm -f "$installer"
    if [ "$rc" -ne 0 ]; then
        ux_error "The official Codex installer failed (exit $rc)."
        return 1
    fi
    if ! CODEX_INSTALLED_VERSION="$(verify_installed_binary "$codex_bin" 2>&1)"; then
        ux_error "Codex CLI binary is not runnable after install: $codex_bin ($CODEX_INSTALLED_VERSION)"
        return 1
    fi
    return 0
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
    local codex_bin resolved
    codex_bin="$(_codex_bin_dir)/codex"
    hash -r
    resolved="$(type -P codex 2>/dev/null || true)"
    if [ -z "$resolved" ]; then
        ux_warning "$(_codex_bin_dir) is not on PATH; add it to run codex."
    elif [ "$resolved" != "$codex_bin" ]; then
        ux_warning "Another Codex executable comes first on PATH: $resolved"
        ux_info "Remove it with its package manager or put $(_codex_bin_dir) earlier in PATH."
    fi
}
