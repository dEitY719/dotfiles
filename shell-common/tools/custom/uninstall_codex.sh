#!/bin/bash
# Codex CLI standalone uninstaller; direct execution needs no sourcing guard.
set -e
source "$(dirname "$0")/init.sh" || exit 1

codex_uninstall_help() {
    ux_info "Usage: codex-uninstall [--help] [--dry-run] [-y|--yes]"
    ux_bullet "Remove verified standalone artifacts; keep configuration, authentication, sessions and skills."
    ux_bullet "npm and other package-manager installations must be removed by their owner."
}

main() {
    local dry_run=0 assume_yes=0 bin_dir codex_home standalone_root name link target found=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            help|-h|--help) codex_uninstall_help; return 0 ;;
            --dry-run) dry_run=1 ;;
            -y|--yes) assume_yes=1 ;;
            *) ux_error "Unknown argument: $1"; codex_uninstall_help; return 2 ;;
        esac
        shift
    done
    bin_dir="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
    codex_home="${CODEX_HOME:-$HOME/.codex}"
    standalone_root="$codex_home/packages/standalone"
    ux_header "Codex CLI Uninstaller"
    ux_info "Configuration, authentication, sessions, and skills will be preserved."
    for name in codex codex-code-mode-host; do
        link="$bin_dir/$name"
        [ -L "$link" ] || continue
        target="$(readlink "$link")"
        case "$target" in
            "$standalone_root/current/bin/$name"|"$standalone_root/current/$name")
                found=1; ux_info "Remove standalone link: $link" ;;
            *) ux_warning "Preserving unrelated link: $link" ;;
        esac
    done
    if [ -L "$codex_home" ]; then
        ux_error "Refusing to remove packages through a symlinked Codex home: $codex_home"
        return 1
    fi
    if [ -L "$codex_home/packages" ]; then
        ux_error "Refusing to remove packages through a symlinked directory: $codex_home/packages"
        return 1
    fi
    if [ -e "$standalone_root" ] || [ -L "$standalone_root" ]; then
        found=1; ux_info "Remove standalone packages: $standalone_root"
    fi
    ux_info "npm and other package-manager installations are retained."
    [ "$found" = 1 ] || { ux_info "No standalone Codex installation found."; return 0; }
    [ "$dry_run" = 0 ] || return 0
    if [ "$assume_yes" = 0 ] && [ ! -t 0 ]; then
        ux_error "Confirmation requires a terminal; use -y to accept the displayed action."
        return 1
    fi
    if [ "$assume_yes" = 0 ] && ! ux_confirm "Remove the displayed standalone Codex files?" "n"; then
        ux_info "Uninstall cancelled."
        return 0
    fi
    for name in codex codex-code-mode-host; do
        link="$bin_dir/$name"
        [ -L "$link" ] || continue
        target="$(readlink "$link")"
        case "$target" in
            "$standalone_root/current/bin/$name"|"$standalone_root/current/$name") rm -f -- "$link" ;;
        esac
    done
    if [ -e "$standalone_root" ] || [ -L "$standalone_root" ]; then
        rm -rf -- "$standalone_root"
    fi
    hash -r
    ux_success "Codex CLI standalone removal completed."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
