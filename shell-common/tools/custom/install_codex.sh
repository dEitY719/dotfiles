#!/bin/bash
# Codex CLI standalone installer and updater (official curl installer).
# Direct-exec installer; no interactive sourcing guard is needed.
set -e

source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1
. "$(dirname "$0")/lib/codex_standalone.sh" || exit 1

codex_install_help() {
    ux_info "Usage: codex-install [-h|--help|help] [--release VER] [--dry-run] [-y|--yes]"
    ux_bullet "Install or update using $CODEX_INSTALLER_URL (curl + sh)."
    ux_bullet "--release VER: install that exact version (pin or downgrade)."
    ux_bullet "Binary: CODEX_INSTALL_DIR (default: ~/.local/bin)."
    ux_bullet "Packages: CODEX_HOME/packages/standalone (CODEX_HOME defaults to ~/.codex)."
    ux_bullet "An existing npm installation is refused; migrate it with codex-update."
    ux_bullet "--dry-run: show actions without downloading or installing."
    ux_bullet "-y, --yes: skip the install confirmation (required without a terminal)."
}

main() {
    local dry_run=0 assume_yes=0 release="" bin_dir codex_bin existing
    local -a installer_args=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            help|-h|--help) codex_install_help; return 0 ;;
            --dry-run) dry_run=1 ;;
            -y|--yes) assume_yes=1 ;;
            --release)
                if [ -z "${2:-}" ] || [ "${2#-}" != "$2" ]; then
                    ux_error "--release requires a version (e.g. --release 0.170.0)"
                    codex_install_help
                    return 2
                fi
                release="$2"
                shift
                ;;
            *) ux_error "Unknown argument: $1"; codex_install_help; return 2 ;;
        esac
        shift
    done
    [ -n "$release" ] && installer_args=(--release "$release")

    bin_dir="$(_codex_bin_dir)"
    codex_bin="$bin_dir/codex"
    ux_header "Codex CLI Standalone Installer"
    ux_info "Installer: $CODEX_INSTALLER_URL (curl + sh)"
    ux_info "Binary: $codex_bin"
    ux_info "Release: ${release:-latest}"
    if [ "$dry_run" = 1 ]; then
        ux_info "[dry-run] Download the official installer, run with sh ${installer_args[*]}, then verify $codex_bin --version."
        return 0
    fi
    ux_require curl || return 1

    # Prepending BIN_DIR avoids upstream editing symlinked shell rc files.
    # Upstream also edits them on a package-manager conflict, so stop before it.
    existing="$(PATH="$bin_dir:$PATH" type -P codex || true)"
    if [ -n "$existing" ] && { [ "$existing" != "$codex_bin" ] || [ "$(_codex_classify_bin "$existing")" != standalone ]; }; then
        ux_error "Another Codex installation exists: $existing"
        ux_info "npm install: run codex-update to migrate it to standalone."
        ux_info "Otherwise: Run codex-uninstall first (use its package manager for Homebrew/Bun installs)."
        return 1
    fi
    if [ "$assume_yes" = 0 ] && [ ! -t 0 ]; then
        ux_error "Confirmation requires a terminal; use -y to accept the displayed action."
        return 1
    fi
    if [ "$assume_yes" = 0 ] && ! ux_confirm "Install or update standalone Codex CLI?" "y"; then
        ux_info "Installation cancelled."
        return 0
    fi

    _codex_standalone_install "${installer_args[@]}" || return 1
    ux_success "Codex CLI is working: $CODEX_INSTALLED_VERSION ($codex_bin)"
    ux_info "Reload your shell, then run codex-version or codex-help."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
