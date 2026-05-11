#!/bin/bash
# shell-common/tools/custom/uninstall_gemini.sh
# Gemini CLI 제거 스크립트 (대화형)

set -e

usage() {
    cat <<'EOF'
Uninstall Gemini CLI (@google/gemini-cli) installed as a global npm package.

Usage:
  uninstall_gemini.sh [-h|--help|help] [--dry-run]

Options:
  -h, --help     Show this help and exit.
  --dry-run      Print the actions without modifying the system.

Verification (after uninstall):
  npm list -g --depth=0
EOF
}

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

DRY_RUN=0
case "${1:-}" in
    help|-h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    "") ;;
    *) ux_error "Unknown argument: $1"; usage >&2; exit 2 ;;
esac

main() {
    clear
    ux_header "Gemini CLI Uninstaller"
    ux_info "This script uninstalls the '@google/gemini-cli' global npm package."
    echo ""
    ux_warning "This is a destructive action that will remove the package from your system."
    [ "$DRY_RUN" = "1" ] && ux_info "(dry-run mode: no commands will execute)"
    echo ""

    local gemini_package="@google/gemini-cli"

    if ! ux_confirm "Are you sure you want to uninstall the '${gemini_package}' package?" "n"; then
        ux_warning "Uninstall cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Check npm
    # ========================================
    ux_step "1/2" "Checking for npm..."
    if ! ux_require "npm"; then exit 1; fi
    ux_success "npm is installed."
    echo ""

    # ========================================
    # Step 2: Uninstall Gemini CLI
    # ========================================
    ux_step "2/2" "Uninstalling ${gemini_package}..."
    if ! have_command gemini; then
        ux_success "Gemini CLI does not appear to be installed. Nothing to do."
    elif [ "$DRY_RUN" = "1" ]; then
        ux_info "[dry-run] npm uninstall -g ${gemini_package}"
    else
        if ! ux_with_spinner "Uninstalling ${gemini_package} via npm" npm uninstall -g "$gemini_package"; then
            ux_error "Uninstallation failed. Please check the errors above."
            exit 1
        fi
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "Gemini CLI Uninstallation Complete"
    if have_command gemini; then
        ux_warning "The 'gemini' command still exists. You may need to check your PATH or restart your shell."
    else
        ux_success "The 'gemini' command has been successfully removed."
    fi
    echo ""
    ux_info "Next: npm list -g --depth=0"
    echo ""
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
