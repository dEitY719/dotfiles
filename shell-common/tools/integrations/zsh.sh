#!/bin/sh
# shell-common/tools/external/zsh.sh
# Auto-generated from bash/app/zsh.bash

# Guard: This file contains bash-only features (export -f)
# Skip loading if not in bash
[ -n "$BASH_VERSION" ] || return 0

# bash/app/zsh.bash
# Bash-specific zsh integration functions
# POSIX-compatible functions are in shell-common/functions/zsh.sh

# ═══════════════════════════════════════════════════════════════
# Bash-Specific Zsh Installation
# ═══════════════════════════════════════════════════════════════

# Install zsh with oh-my-zsh and plugins (bash-specific)
install-zsh() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_zsh.sh" "$@"
}

# ═══════════════════════════════════════════════════════════════
# Shell Switching (SSOT: shell-common/functions/shell_switch.sh)
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# Bash Quick Aliases
# ═══════════════════════════════════════════════════════════════

alias zsh-switch='zsh_switch'
alias bash-switch='bash_switch'
alias zsh-to='zsh_switch'
alias bash-to='bash_switch'
alias zsh-config='cat ~/.zshrc'                    # View zsh config
alias zsh-edit-quick='nano ~/.zshrc'               # Quick edit
alias zsh-info='zsh --version && echo && uname -a' # Zsh system info

# ═══════════════════════════════════════════════════════════════
# Register Help & Export Functions (Bash-Specific)
# Note: HELP_DESCRIPTIONS defaults are centrally defined in my_help.sh
# ═══════════════════════════════════════════════════════════════

# Export functions for use in other shells
# (POSIX functions are auto-loaded from shell-common/)
export -f install-zsh
