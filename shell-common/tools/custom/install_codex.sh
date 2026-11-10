#!/bin/bash
# Direct-exec installer; no interactive sourcing guard is needed.
set -e

source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

codex_install_help() {
    ux_info "Usage: codex-install [-h|--help|help] [--dry-run]"
    ux_bullet "Install or update using https://chatgpt.com/codex/install.sh (curl + sh)."
    ux_bullet "Binary: CODEX_INSTALL_DIR (default: ~/.local/bin)."
    ux_bullet "Packages: CODEX_HOME/packages/standalone (CODEX_HOME defaults to ~/.codex)."
    ux_bullet "Remove an existing npm installation with codex-uninstall first."
    ux_bullet "--dry-run: show actions without downloading or installing."
}

main() {
    local dry_run=0 bin_dir codex_bin existing codex_version
    while [ "$#" -gt 0 ]; do
        case "$1" in
            help|-h|--help) codex_install_help; return 0 ;;
            --dry-run) dry_run=1 ;;
            *) ux_error "Unknown argument: $1"; codex_install_help; return 2 ;;
        esac
        shift
    done

    bin_dir="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
    codex_bin="$bin_dir/codex"
    ux_header "Codex CLI Standalone Installer"
    ux_info "Installer: https://chatgpt.com/codex/install.sh (curl + sh)"
    ux_info "Binary: $codex_bin"
    if [ "$dry_run" = 1 ]; then
        ux_info "[dry-run] Download the official installer, run with sh, then verify $codex_bin --version."
        return 0
    fi
    ux_require curl || return 1

    # Prepending BIN_DIR avoids upstream editing symlinked shell rc files.
    # Upstream also edits them on a package-manager conflict, so stop before it.
    existing="$(PATH="$bin_dir:$PATH" type -P codex || true)"
    if [ -n "$existing" ] && [ "$existing" != "$codex_bin" ]; then
        ux_error "Another Codex installation exists: $existing"
        ux_info "Run codex-uninstall first (use its package manager for Homebrew/Bun installs)."
        return 1
    fi
    if ! ux_confirm "Install or update standalone Codex CLI?" "y"; then
        ux_info "Installation cancelled."
        return 0
    fi

    _codex_installer_temp="$(mktemp)" || return 1
    trap 'rm -f "$_codex_installer_temp"' EXIT
    if ! curl -fsSL https://chatgpt.com/codex/install.sh -o "$_codex_installer_temp"; then
        ux_error "Failed to download the official Codex installer."
        return 1
    fi
    if ! PATH="$bin_dir:$PATH" sh "$_codex_installer_temp"; then
        ux_error "Codex CLI installation failed."
        return 1
    fi
    if ! codex_version="$(verify_installed_binary "$codex_bin" 2>&1)"; then
        ux_error "Codex CLI binary is not runnable: $codex_bin ($codex_version)"
        return 1
    fi
    ux_success "Codex CLI is working: $codex_version ($codex_bin)"
    ux_info "Reload your shell, then run codex-version or codex-help."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
