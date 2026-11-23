#!/bin/bash
# Codex CLI updater: refresh a standalone install or migrate an npm one
# to the official standalone installer (issue #2426).
# Direct-exec updater; no interactive sourcing guard is needed.
set -e

source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1
. "$(dirname "$0")/lib/codex_standalone.sh" || exit 1

codex_update_help() {
    ux_info "Usage: codex-update [-h|--help|help] [--release VER] [--dry-run] [-y|--yes]"
    ux_bullet "standalone: re-run $CODEX_INSTALLER_URL and report the version change."
    ux_bullet "npm: confirm, npm uninstall -g $CODEX_NPM_PACKAGE, then install standalone."
    ux_bullet "Homebrew/Bun/manual installs are never changed; remove them yourself."
    ux_bullet "--release VER: install that exact version (pin or downgrade)."
    ux_bullet "-y, --yes: skip the npm migration confirmation."
    ux_bullet "--dry-run: show the detected method and planned steps (no network, no npm)."
    ux_bullet "Configuration, authentication, sessions, and skills are preserved."
}

_codex_update_plan() {
    local method="$1" release="$2"
    case "$method" in
        standalone)
            ux_info "[dry-run] Record codex --version, run the official installer${release:+ --release $release}, verify, report the change."
            ;;
        npm)
            ux_info "[dry-run] Confirm, run npm uninstall -g $CODEX_NPM_PACKAGE, then install standalone${release:+ --release $release} and verify."
            ;;
    esac
}

_codex_update_refuse() {
    case "$1" in
        none)
            ux_error "Codex CLI is not installed."
            ux_info "Run codex-install first."
            ;;
        other)
            ux_error "Codex CLI is not a standalone or npm install: $CODEX_EXISTING_BIN"
            ux_info "Remove it with its package manager (brew uninstall codex, bun remove -g $CODEX_NPM_PACKAGE), then run codex-install."
            ;;
    esac
}

main() {
    local dry_run=0 assume_yes=0 release="" bin_dir codex_bin method before after
    local -a installer_args=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            help|-h|--help) codex_update_help; return 0 ;;
            --dry-run) dry_run=1 ;;
            -y|--yes) assume_yes=1 ;;
            --release)
                if [ -z "${2:-}" ] || [ "${2#-}" != "$2" ]; then
                    ux_error "--release requires a version (e.g. --release 0.170.0)"
                    codex_update_help
                    return 2
                fi
                release="$2"
                shift
                ;;
            *) ux_error "Unknown argument: $1"; codex_update_help; return 2 ;;
        esac
        shift
    done
    [ -n "$release" ] && installer_args=(--release "$release")

    bin_dir="$(_codex_bin_dir)"
    codex_bin="$bin_dir/codex"
    if [ "$dry_run" = 1 ]; then
        _codex_detect_install --no-npm
    else
        _codex_detect_install
    fi
    method="$CODEX_INSTALL_METHOD"

    ux_header "Codex CLI Updater"
    ux_info "Install method: $method"
    ux_info "Binary: $codex_bin"
    ux_info "Release: ${release:-latest}"
    [ "$dry_run" = 1 ] && ux_info "[dry-run] npm was not queried; detection used the codex on PATH."
    case "$method" in
        none|other) _codex_update_refuse "$method"; return 1 ;;
    esac
    if [ "$dry_run" = 1 ]; then
        _codex_update_plan "$method" "$release"
        return 0
    fi
    ux_require curl || return 1

    if [ "$method" = npm ]; then
        if ! _codex_npm_root_writable; then
            ux_error "The npm global root is not writable: $CODEX_NPM_ROOT"
            ux_info "Remove the package with sudo, then install standalone:"
            ux_bullet "sudo npm uninstall -g $CODEX_NPM_PACKAGE"
            ux_bullet "codex-install${release:+ --release $release}"
            return 1
        fi
        if [ "$assume_yes" = 0 ] &&
            ! ux_confirm "Migrate the npm Codex CLI to the official standalone install?" "y"; then
            ux_info "Migration cancelled; nothing was changed."
            return 0
        fi
        before="unknown"
        if [ -n "$CODEX_EXISTING_BIN" ]; then
            before="$("$CODEX_EXISTING_BIN" --version 2>/dev/null || printf 'unknown')"
        fi
        # Download first: a network failure must not leave the user without codex.
        _codex_fetch_installer || return 1
        _codex_migrate_from_npm || return 1
        if ! _codex_run_installer "${installer_args[@]}"; then
            ux_error "The npm package was removed, so no Codex CLI is installed right now."
            ux_info "Retry: codex-install${release:+ --release $release}"
            return 1
        fi
        ux_success "Migrated npm -> standalone: $before -> $CODEX_INSTALLED_VERSION ($codex_bin)"
    else
        before="$("$codex_bin" --version 2>/dev/null || printf 'unknown')"
        _codex_standalone_install "${installer_args[@]}" || return 1
        after="$CODEX_INSTALLED_VERSION"
        if [ "$before" = "$after" ]; then
            ux_success "Codex CLI already up to date ($after)"
        else
            ux_success "Codex CLI updated: $before -> $after"
        fi
        if [ "$CODEX_NPM_PRESENT" = 1 ]; then
            ux_warning "A legacy npm $CODEX_NPM_PACKAGE is still installed next to standalone."
            ux_info "Remove it: npm uninstall -g $CODEX_NPM_PACKAGE"
        fi
    fi
    _codex_warn_path_shadow
    ux_info "Run hash -r or open a new shell to pick up the new binary."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
