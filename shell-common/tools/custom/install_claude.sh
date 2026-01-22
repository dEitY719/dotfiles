#!/bin/sh
# shell-common/tools/custom/install_claude.sh
# Claude Code CLI Install Script
# Uses official native installer (recommended by Anthropic)
# Reference: https://code.claude.com/docs/en/getting-started

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

main() {
    clear
    ux_header "Claude Code CLI Installer"
    ux_info "Installing Claude Code using official native installer..."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Detect OS and check compatibility
    # ========================================
    ux_step "1/2" "Detecting operating system..."

    if command -v claude &>/dev/null; then
        ux_warning "Claude Code CLI seems to be already installed."
        if ! ux_confirm "Do you want to reinstall/update it?" "y"; then
            ux_info "Installation skipped."
            exit 0
        fi
    fi
    echo ""

    # ========================================
    # Step 2: Install using official native installer
    # ========================================
    ux_step "2/2" "Installing Claude Code..."

    case "$OSTYPE" in
        darwin* | linux* | linux-gnu* | freebsd*)
            # macOS, Linux, WSL - use bash installer
            ux_info "Platform: ${OSTYPE} (using bash installer)"
            if ! ux_with_spinner "Installing Claude Code" \
                bash -c 'curl -fsSL https://claude.ai/install.sh | bash'; then
                ux_error "Claude Code CLI installation failed."
                ux_info "Please check your internet connection and try again."
                exit 1
            fi
            ;;
        msys | msys* | win32 | cygwin)
            # Windows (Git Bash, Cygwin)
            ux_error "Windows detected in Git Bash/Cygwin environment"
            echo ""
            ux_info "For Windows, please use native PowerShell or CMD:"
            ux_section "PowerShell (Recommended)"
            ux_bullet "Run: ${UX_INFO}irm https://claude.ai/install.ps1 | iex${UX_RESET}"
            ux_section "Command Prompt (CMD)"
            ux_bullet "Run: ${UX_INFO}curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd${UX_RESET}"
            exit 1
            ;;
        *)
            ux_error "Unsupported operating system: $OSTYPE"
            exit 1
            ;;
    esac

    # ========================================
    # Step 3: Verification
    # ========================================
    echo ""
    ux_header "✅ Claude Code CLI Setup Complete!"
    ux_section "Verification"

    if command -v claude &>/dev/null; then
        claude --version
        ux_success "Claude CLI is ready to use."
        echo ""
        ux_section "Next Steps"
        ux_bullet "Start Claude Code: ${UX_INFO}claude${UX_RESET}"
        ux_bullet "Check installation: ${UX_INFO}claude doctor${UX_RESET}"
        ux_bullet "View settings: ${UX_INFO}claude /config${UX_RESET}"
    else
        ux_warning "Claude command not found after installation."
        ux_info "Possible solutions:"
        ux_bullet "Restart your terminal"
        ux_bullet "Run: ${UX_INFO}source ~/.bashrc${UX_RESET} or ${UX_INFO}source ~/.zshrc${UX_RESET}"
        ux_bullet "Check PATH includes: ${UX_INFO}~/.local/bin${UX_RESET}"
    fi
    echo ""
}

# Execute only if run directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ "${0##*/}" = "install_claude.sh" ]; then
    main "$@"
fi
