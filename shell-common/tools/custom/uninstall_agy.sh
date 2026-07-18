#!/bin/bash
# shell-common/tools/custom/uninstall_agy.sh
# Antigravity CLI (agy) 제거 스크립트 (대화형)

set -e

usage() {
    cat <<'EOF'
Uninstall the Antigravity CLI (agy) binary installed at ~/.local/bin/agy.

Usage:
  uninstall_agy.sh [-h|--help|help] [--dry-run]

Options:
  -h, --help     Show this help and exit.
  --dry-run      Print the actions without modifying the system.

Verification (after uninstall):
  command -v agy
EOF
}

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

AGY_BIN="${HOME}/.local/bin/agy"

DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        help|-h|--help) usage; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        *) ux_error "Unknown argument: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

main() {
    clear
    ux_header "Antigravity CLI (agy) Uninstaller"
    ux_info "This script removes the agy binary at ${AGY_BIN}."
    echo ""
    [ "$DRY_RUN" = "1" ] && ux_info "(dry-run mode: no commands will execute)"
    echo ""

    # ========================================
    # Step 1: Check if installed (idempotent)
    # ========================================
    ux_step "1/2" "Checking for agy binary..."
    if [ ! -e "$AGY_BIN" ] && ! have_command agy; then
        ux_success "agy is not installed. Nothing to do. (이미 제거됨)"
        echo ""
        exit 0
    fi
    ux_success "agy binary found."
    echo ""

    ux_warning "This is a destructive action that removes ${AGY_BIN}."
    if ! ux_confirm "Are you sure you want to uninstall agy?" "n"; then
        ux_warning "Uninstall cancelled."
        exit 0
    fi

    # ========================================
    # Step 2: Remove agy binary
    # ========================================
    ux_step "2/2" "Removing ${AGY_BIN}..."
    if [ "$DRY_RUN" = "1" ]; then
        ux_info "[dry-run] rm -f ${AGY_BIN}"
    else
        if [ -e "$AGY_BIN" ]; then
            rm -f "$AGY_BIN" || { ux_error "Failed to remove ${AGY_BIN}."; exit 1; }
        fi
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "Antigravity CLI Uninstallation Complete"
    if [ "$DRY_RUN" != "1" ] && have_command agy; then
        ux_warning "The 'agy' command still exists on PATH."
        ux_info "It may be installed elsewhere; check: ${UX_PRIMARY}command -v agy${UX_RESET}"
    else
        ux_success "The 'agy' command has been removed."
    fi
    echo ""
    ux_info "Next: command -v agy"
    echo ""
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
