#!/bin/bash
# Codex CLI uninstaller for standalone and legacy npm installations.
# Direct-exec uninstaller; no interactive sourcing guard is needed.
set -e

source "$(dirname "$0")/init.sh" || exit 1

codex_uninstall_help() {
    ux_info "Usage: codex-uninstall [-h|--help|help] [--dry-run]"
    ux_bullet "Remove standalone Codex and the legacy global @openai/codex npm package."
    ux_bullet "Standalone binary: CODEX_INSTALL_DIR (default: ~/.local/bin)."
    ux_bullet "Standalone packages: CODEX_HOME/packages/standalone (default home: ~/.codex)."
    ux_bullet "Preserve configuration, authentication, sessions, and skills."
    ux_bullet "--dry-run: show actions without removing files or prompting."
}

main() {
    local dry_run=0 bin_dir codex_home standalone_root npm_root="" npm_installed=0
    local name link target found=0 remaining
    while [ "$#" -gt 0 ]; do
        case "$1" in
            help|-h|--help) codex_uninstall_help; return 0 ;;
            --dry-run) dry_run=1 ;;
            *) ux_error "Unknown argument: $1"; codex_uninstall_help; return 2 ;;
        esac
        shift
    done

    bin_dir="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
    codex_home="${CODEX_HOME:-$HOME/.codex}"
    standalone_root="$codex_home/packages/standalone"
    if command -v npm >/dev/null 2>&1; then
        if ! npm_root="$(npm root -g)" || [ -z "$npm_root" ]; then
            ux_error "Cannot locate global npm packages."
            return 1
        fi
        if [ -d "$npm_root/@openai/codex" ]; then
            npm_installed=1
        fi
    fi

    ux_header "Codex CLI Uninstaller"
    ux_info "Configuration, authentication, sessions, and skills will be preserved."
    [ "$dry_run" = 1 ] && ux_info "[dry-run] No files will be removed."
    if [ "$dry_run" = 0 ] && ! ux_confirm "Remove standalone and legacy npm Codex installations?" "n"; then
        ux_info "Uninstall cancelled."
        return 0
    fi

    # Remove only links created by the official installer, including broken ones.
    for name in codex codex-code-mode-host; do
        link="$bin_dir/$name"
        [ -L "$link" ] || continue
        target="$(readlink "$link")"
        case "$target" in
            "$standalone_root/current/bin/$name"|"$standalone_root/current/$name")
                found=1
                ux_info "Remove standalone link: $link"
                [ "$dry_run" = 1 ] || rm -f -- "$link"
                ;;
            *) ux_warning "Preserving unrelated link: $link" ;;
        esac
    done
    if [ -e "$standalone_root" ] || [ -L "$standalone_root" ]; then
        found=1
        ux_info "Remove standalone packages: $standalone_root"
        [ "$dry_run" = 1 ] || rm -rf -- "$standalone_root"
    fi
    if [ "$npm_installed" = 1 ]; then
        found=1
        ux_info "Remove legacy npm package: npm uninstall -g @openai/codex"
        if [ "$dry_run" = 0 ] && ! npm uninstall -g @openai/codex; then
            ux_error "Failed to uninstall the legacy npm package."
            return 1
        fi
    fi
    [ "$found" = 1 ] || ux_info "No standalone or legacy npm Codex installation found."
    if [ "$dry_run" = 1 ]; then
        return 0
    fi
    hash -r
    remaining="$(type -P codex || true)"
    if [ -n "$remaining" ]; then
        ux_warning "Another Codex executable remains: $remaining"
        ux_info "Check CODEX_INSTALL_DIR/CODEX_HOME or remove it using its package manager."
    fi
    ux_success "Codex CLI removal completed."
    ux_info "Next: codex-install (or curl -fsSL https://chatgpt.com/codex/install.sh | sh)."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
