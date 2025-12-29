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
