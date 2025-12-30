#!/bin/sh
# shell-common/functions/p10k.sh
# Powerlevel10k theme helper functions (POSIX-compatible)
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Powerlevel10k Help Function
# ═══════════════════════════════════════════════════════════════

# Main help function for powerlevel10k font setup
p10k_help() {
    ux_header "Powerlevel10k Font Setup for VSCode Terminal"

    ux_section "VS Code Settings (settings.json)"
    ux_info "Open settings with: ${UX_BOLD}Ctrl+Shift+P${UX_RESET} → Preference: Open User Settings (JSON)"
    echo ""

    ux_section "Add These Lines to settings.json"
    cat <<'EOF'
  "editor.fontFamily": "D2Coding, Consolas, 'Courier New', monospace, 'MesloLGS NF'",
  "editor.fontSize": 14,
  "terminal.integrated.fontFamily": "MesloLGS NF",
  "terminal.integrated.fontSize": 14,
EOF
    echo ""
    echo ""

    ux_section "Installation Steps"
    ux_bullet "1. Install powerlevel10k: ${UX_BOLD}install-p10k${UX_RESET}"
    ux_bullet "2. Configure p10k: ${UX_BOLD}p10k configure${UX_RESET}}"
    ux_bullet "3. Select font preference in configuration wizard"
    ux_bullet "4. Add settings above to VSCode settings.json"
    ux_bullet "5. Restart VSCode terminal"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "Font not showing? MesloLGS NF font may not be installed"
    ux_bullet "Install MesloLGS NF: Visit ${UX_BOLD}https://www.nerdfonts.com/font-downloads${UX_RESET}"
    ux_bullet "Or use: ${UX_BOLD}brew install --cask font-meslo-lg-nerd-font${UX_RESET}} (macOS)"
    ux_bullet "After installation, restart VSCode completely"
    echo ""

    ux_section "Alternative Fonts"
    ux_bullet "FiraCode Nerd Font"
    ux_bullet "JetBrains Mono Nerd Font"
    ux_bullet "Hack Nerd Font"
    echo ""

    ux_section "Verify Installation"
    ux_info "Run: ${UX_BOLD}p10k configure${UX_RESET}} to test font rendering"
    ux_info "Or check theme: ${UX_BOLD}zsh-theme-current${UX_RESET}}"
    echo ""
}

# Alias for p10k-help format (using dash instead of underscore)
alias p10k-help='p10k_help'
