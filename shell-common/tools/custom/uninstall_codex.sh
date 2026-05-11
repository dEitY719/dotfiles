#!/bin/bash
# shell-common/tools/custom/uninstall_codex.sh
# Codex CLI 제거 스크립트 (대화형)

set -e

usage() {
    cat <<'EOF'
Uninstall Codex CLI (@openai/codex) installed as a global npm package.

Usage:
  uninstall_codex.sh [-h|--help|help] [--dry-run]

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
    ux_header "Codex CLI Uninstaller"
    ux_info "This script uninstalls the '@openai/codex' global npm package."
    echo ""
    ux_warning "This is a destructive action and will remove the package from your system."
    [ "$DRY_RUN" = "1" ] && ux_info "(dry-run mode: no commands will execute)"
    echo ""

    local codex_package="@openai/codex"

    if ! ux_confirm "Are you sure you want to uninstall the '${codex_package}' package?" "n"; then
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
    # Step 2: Uninstall Codex CLI
    # ========================================
    ux_step "2/2" "Uninstalling ${codex_package}..."
    if ! have_command codex; then
        ux_success "Codex CLI does not appear to be installed. Nothing to do."
    elif [ "$DRY_RUN" = "1" ]; then
        ux_info "[dry-run] npm uninstall -g ${codex_package}"
    else
        if ! ux_with_spinner "Uninstalling ${codex_package} via npm" npm uninstall -g "$codex_package"; then
            ux_error "Uninstallation failed. Please check the errors above."
            exit 1
        fi
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    local removal_failures=0
    ux_header "Codex CLI Uninstallation Complete"
    if have_command codex; then
        ux_warning "The 'codex' command still exists."
        ux_info "You may need to check your PATH or restart your shell."
        removal_failures=$((removal_failures + 1))
    else
        ux_success "The 'codex' command has been successfully removed."
    fi

    if [ "$removal_failures" -eq 0 ]; then
        ux_success "All removal steps completed cleanly."
    else
        ux_warning "Completed with $removal_failures non-fatal warning(s)."
        ux_info "See output above for details."
    fi
    echo ""
    ux_info "Next: npm list -g --depth=0"
    echo ""
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
