#!/bin/bash

# bash/app/zsh.bash
# Bash-specific zsh integration functions
# POSIX-compatible functions are in shell-common/functions/zsh.sh

# ═══════════════════════════════════════════════════════════════
# Bash-Specific Zsh Installation
# ═══════════════════════════════════════════════════════════════

# Install zsh with oh-my-zsh and plugins (bash-specific)
install-zsh() {
    bash "$HOME/dotfiles/mytool/install-zsh.sh" "$@"
}

# ═══════════════════════════════════════════════════════════════
# Bash-Specific Shell Switching
# ═══════════════════════════════════════════════════════════════

# Switch to zsh shell (bash-specific version)
zsh-switch() {
    if command -v zsh &>/dev/null; then
        ux_success "Switching to zsh..."
        exec zsh -i
    else
        ux_error "zsh is not installed. Run 'install-zsh' to install it."
        return 1
    fi
}

# Switch to bash shell (bash-specific version)
bash-switch() {
    if command -v bash &>/dev/null; then
        ux_success "Switching to bash..."
        exec bash -i
    else
        ux_error "bash is not installed."
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Bash Quick Aliases
# ═══════════════════════════════════════════════════════════════

alias zsh-config='cat ~/.zshrc'                    # View zsh config
alias zsh-edit-quick='nano ~/.zshrc'               # Quick edit
alias zsh-info='zsh --version && echo && uname -a' # Zsh system info

# ═══════════════════════════════════════════════════════════════
# Register Help & Export Functions (Bash-Specific)
# ═══════════════════════════════════════════════════════════════

# Register help function description
# shellcheck disable=SC2034
HELP_DESCRIPTIONS["zsh-help"]="Zsh shell management commands"

# Export functions for use in other shells
# (POSIX functions are auto-loaded from shell-common/)
export -f install-zsh zsh-switch bash-switch
