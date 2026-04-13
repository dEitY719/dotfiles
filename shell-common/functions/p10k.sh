#!/bin/sh
# shell-common/functions/p10k.sh
# Powerlevel10k theme helper functions (POSIX-compatible)
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Powerlevel10k Help Function
# ═══════════════════════════════════════════════════════════════

_p10k_help_summary() {
    ux_info "Usage: p10k-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "vscode: Ctrl+Shift+P → Open User Settings (JSON)"
    ux_bullet_sub "settings: editor.fontFamily | terminal.integrated.fontFamily"
    ux_bullet_sub "install: install-p10k | p10k configure | font setup"
    ux_bullet_sub "trouble: missing MesloLGS NF | nerdfonts.com | brew cask"
    ux_bullet_sub "fonts: FiraCode | JetBrains Mono | Hack Nerd Font"
    ux_bullet_sub "verify: p10k configure | zsh-theme-current"
    ux_bullet_sub "details: p10k-help <section>  (example: p10k-help install)"
}

_p10k_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "vscode"
    ux_bullet_sub "settings"
    ux_bullet_sub "install"
    ux_bullet_sub "trouble"
    ux_bullet_sub "fonts"
    ux_bullet_sub "verify"
}

_p10k_help_rows_vscode() {
    ux_info "Open settings with: ${UX_BOLD}Ctrl+Shift+P${UX_RESET} → Preference: Open User Settings (JSON)"
}

_p10k_help_rows_settings() {
    cat <<'EOF'
  "editor.fontFamily": "D2Coding, Consolas, 'Courier New', monospace, 'MesloLGS NF'",
  "editor.fontSize": 14,
  "terminal.integrated.fontFamily": "MesloLGS NF",
  "terminal.integrated.fontSize": 14,
EOF
}

_p10k_help_rows_install() {
    ux_bullet "1. Install powerlevel10k: ${UX_BOLD}install-p10k${UX_RESET}"
    ux_bullet "2. Configure p10k: ${UX_BOLD}p10k configure${UX_RESET}"
    ux_bullet "3. Select font preference in configuration wizard"
    ux_bullet "4. Add settings above to VSCode settings.json"
    ux_bullet "5. Restart VSCode terminal"
}

_p10k_help_rows_trouble() {
    ux_bullet "Font not showing? MesloLGS NF font may not be installed"
    ux_bullet "Install MesloLGS NF: Visit ${UX_BOLD}https://www.nerdfonts.com/font-downloads${UX_RESET}"
    ux_bullet "Or use: ${UX_BOLD}brew install --cask font-meslo-lg-nerd-font${UX_RESET} (macOS)"
    ux_bullet "After installation, restart VSCode completely"
}

_p10k_help_rows_fonts() {
    ux_bullet "FiraCode Nerd Font"
    ux_bullet "JetBrains Mono Nerd Font"
    ux_bullet "Hack Nerd Font"
}

_p10k_help_rows_verify() {
    ux_info "Run: ${UX_BOLD}p10k configure${UX_RESET} to test font rendering"
    ux_info "Or check theme: ${UX_BOLD}zsh-theme-current${UX_RESET}"
}

_p10k_help_render_section() {
    ux_section "$1"
    "$2"
}

_p10k_help_section_rows() {
    case "$1" in
        vscode|code)             _p10k_help_rows_vscode ;;
        settings|json|config)    _p10k_help_rows_settings ;;
        install|setup|steps)     _p10k_help_rows_install ;;
        trouble|troubleshooting) _p10k_help_rows_trouble ;;
        fonts|font|alternatives) _p10k_help_rows_fonts ;;
        verify|test)             _p10k_help_rows_verify ;;
        *)
            ux_error "Unknown p10k-help section: $1"
            ux_info "Try: p10k-help --list"
            return 1
            ;;
    esac
}

_p10k_help_full() {
    ux_header "Powerlevel10k Font Setup for VSCode Terminal"
    _p10k_help_render_section "VS Code Settings (settings.json)" _p10k_help_rows_vscode
    _p10k_help_render_section "Add These Lines to settings.json" _p10k_help_rows_settings
    _p10k_help_render_section "Installation Steps" _p10k_help_rows_install
    _p10k_help_render_section "Troubleshooting" _p10k_help_rows_trouble
    _p10k_help_render_section "Alternative Fonts" _p10k_help_rows_fonts
    _p10k_help_render_section "Verify Installation" _p10k_help_rows_verify
}

# Main help function for powerlevel10k font setup
p10k_help() {
    case "${1:-}" in
        ""|-h|--help|help) _p10k_help_summary ;;
        --list|list|section|sections)        _p10k_help_list_sections ;;
        --all|all)          _p10k_help_full ;;
        *)                  _p10k_help_section_rows "$1" ;;
    esac
}

# Alias for p10k-help format (using dash instead of underscore)
alias p10k-help='p10k_help'
