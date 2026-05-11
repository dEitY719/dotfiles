#!/bin/bash
# shell-common/tools/custom/uninstall_npm.sh
# Node.js & npm 제거 스크립트 (대화형)

set -e

usage() {
    cat <<'EOF'
Uninstall apt-installed Node.js / npm and optionally their user config.

Usage:
  uninstall_npm.sh [-h|--help|help] [--dry-run] [--keep-config]

Options:
  -h, --help      Show this help and exit.
  --dry-run       Print actions without executing them.
  --keep-config   Skip the prompts that remove ~/.npm-global, ~/.npm,
                  and ~/.npmrc.

Verification (after uninstall):
  hash -r && command -v node && command -v npm
EOF
}

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

DRY_RUN=0
KEEP_CONFIG=0
while [ $# -gt 0 ]; do
    case "$1" in
        help|-h|--help) usage; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        --keep-config) KEEP_CONFIG=1 ;;
        *) ux_error "Unknown argument: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

main() {
    clear
    ux_header "Node.js & npm Uninstaller"
    ux_info "This script uninstalls Node.js and npm installed via apt."
    echo ""
    ux_warning "This is a destructive action."
    ux_error "This can also remove your global npm packages and configuration files."
    [ "$DRY_RUN" = "1" ] && ux_info "(dry-run mode: no commands will execute)"
    [ "$KEEP_CONFIG" = "1" ] && ux_info "(--keep-config: skipping config removal prompts)"
    echo ""

    if ! ux_confirm "Are you sure you want to uninstall the Node.js and npm apt packages?" "n"; then
        ux_warning "Uninstallation cancelled."
        exit 0
    fi

    # Request sudo privileges
    ux_info "Requesting sudo privileges..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done >/dev/null 2>&1 &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    local removal_failures=0

    # ========================================
    # Step 1: Remove Node.js & npm packages
    # ========================================
    ux_step "1/3" "Uninstalling Node.js and npm packages..."
    if [ "$DRY_RUN" = "1" ]; then
        ux_info "[dry-run] sudo apt-get remove -y nodejs npm"
    elif ! ux_with_spinner "Removing nodejs and npm apt packages" sudo apt-get remove -y nodejs npm; then
        ux_warning "Could not remove nodejs and npm packages. They may not have been installed."
        removal_failures=$((removal_failures + 1))
    else
        ux_success "Node.js and npm packages removed."
    fi

    if ux_confirm "Run 'apt-get autoremove' to clean up unused dependencies?" "y"; then
        if [ "$DRY_RUN" = "1" ]; then
            ux_info "[dry-run] sudo apt-get autoremove -y"
        elif ! ux_with_spinner "Autoremoving unused dependencies" sudo apt-get autoremove -y; then
            ux_warning "apt autoremove failed."
        fi
    fi
    echo ""

    # ========================================
    # Step 2: Clean npm configuration
    # ========================================
    ux_step "2/3" "Cleaning up npm configuration and data..."
    if [ "$KEEP_CONFIG" = "1" ]; then
        ux_info "Skipping config removal (--keep-config)."
    else
        if [ -d "$HOME/.npm-global" ] && ux_confirm "Remove user-level global packages directory (~/.npm-global)?" "n"; then
            if [ "$DRY_RUN" = "1" ]; then
                ux_info "[dry-run] rm -rf $HOME/.npm-global"
            else
                rm -rf "$HOME/.npm-global"
                ux_success "Removed ~/.npm-global directory."
            fi
        fi
        if [ -d "$HOME/.npm" ] && ux_confirm "Remove npm cache directory (~/.npm)?" "n"; then
            if [ "$DRY_RUN" = "1" ]; then
                ux_info "[dry-run] rm -rf $HOME/.npm"
            else
                rm -rf "$HOME/.npm"
                ux_success "Removed ~/.npm directory."
            fi
        fi
        if [ -f "$HOME/.npmrc" ] && ux_confirm "Remove npm configuration file (~/.npmrc)?" "n"; then
            if [ "$DRY_RUN" = "1" ]; then
                ux_info "[dry-run] rm -f $HOME/.npmrc"
            else
                rm -f "$HOME/.npmrc"
                ux_success "Removed ~/.npmrc file."
            fi
        fi
    fi
    echo ""

    # ========================================
    # Step 3: Verify uninstallation
    # ========================================
    ux_step "3/3" "Verifying uninstallation..."
    if have_command node || have_command npm; then
        ux_warning "A 'node' or 'npm' command still exists."
        ux_info "This could be from NVM or another installation method. Check your PATH."
        command -v node || true
        command -v npm || true
        removal_failures=$((removal_failures + 1))
    else
        ux_success "Node.js and npm have been successfully removed from apt."
    fi

    # Clean up sudo keep-alive
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "Node.js & npm Uninstallation Complete"
    if [ "$removal_failures" -eq 0 ]; then
        ux_success "All removal steps completed cleanly."
    else
        ux_warning "Completed with $removal_failures non-fatal warning(s) — see output above."
    fi
    echo ""
    ux_info "Next: hash -r && command -v node && command -v npm"
    echo ""
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
