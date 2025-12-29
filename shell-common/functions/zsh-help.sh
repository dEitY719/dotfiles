#!/bin/sh
# shell-common/functions/zsh-help.sh
# zsh-Help - shared between bash and zsh

# Keeps current session and directory context
bash-switch() {
    ux_success "Switching to bash..."
    exec bash -i
}

# Shorthand for zsh switch
alias zsh-to='zsh-switch'
alias bash-to='bash-switch'

# ═══════════════════════════════════════════════════════════════
# Zsh Configuration Management
# ═══════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────
# Required Packages for Enhanced Zsh
# ─────────────────────────────────────────────────────────────────
# install-p10k  - Install powerlevel10k theme for modern zsh prompt
#
# Note: powerlevel10k requires:
#   - git (for cloning the theme repository)
#   - oh-my-zsh (installed via install-zsh)
#   - Recommended: A patched font (Nerd Font) for better visual appearance

# Check if zsh is installed
_zsh_check_installed() {
    if ! command -v zsh &>/dev/null; then
        ux_error "zsh is not installed."
        ux_info "Install with: ${UX_BOLD}install-zsh${UX_RESET}"
        return 1
    fi
    return 0
}

# Check if oh-my-zsh is installed
_zsh_check_omz() {
    if [ ! -d "${HOME}/.oh-my-zsh" ]; then
        ux_warning "oh-my-zsh is not installed."
        ux_info "Install with: ${UX_BOLD}install-zsh${UX_RESET}"
        return 1
    fi
    return 0
}

# Get current zsh version
zsh-version() {
    if _zsh_check_installed; then
        zsh --version
    fi
}

# List all available zsh themes
zsh-themes() {
    if ! _zsh_check_omz; then
        return 1
    fi

    ux_header "Available Zsh Themes"
    ux_info "Located in: ${UX_BOLD}~/.oh-my-zsh/themes/${UX_RESET}"
    echo ""

    local themes_dir="${HOME}/.oh-my-zsh/themes"
    if [ -d "$themes_dir" ]; then
        echo "Available themes:"
        find "$themes_dir" -maxdepth 1 -name "*.zsh-theme" -printf '%f\n' | sed 's/\.zsh-theme$//' | sort | nl
    else
        ux_error "Themes directory not found."
        return 1
    fi
}