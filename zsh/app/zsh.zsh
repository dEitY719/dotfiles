#!/bin/zsh

# zsh/app/zsh.zsh
# Zsh-specific shell integration functions
# POSIX-compatible functions are in shell-common/functions/zsh.sh

# ═══════════════════════════════════════════════════════════════
# Shell Switching (SSOT: shell-common/functions/shell_switch.sh)
# ═══════════════════════════════════════════════════════════════
alias zsh-switch='zsh_switch'
alias bash-switch='bash_switch'
alias zsh-to='zsh_switch'
alias bash-to='bash_switch'

# ═══════════════════════════════════════════════════════════════
# Zsh Quick Aliases
# ═══════════════════════════════════════════════════════════════

alias zsh-config='cat ~/.zshrc'                    # View zsh config
alias zsh-edit-quick='nano ~/.zshrc'               # Quick edit
alias zsh-info='zsh --version && echo && uname -a' # Zsh system info

# ═══════════════════════════════════════════════════════════════
# Zsh Help Registration
# Note: HELP_DESCRIPTIONS defaults are centrally defined in my_help.sh
# ═══════════════════════════════════════════════════════════════

# Note: In zsh, all functions are automatically available without explicit export
# (export -f is bash syntax and not needed in zsh)
# POSIX-compatible functions are auto-loaded from shell-common/functions/zsh.sh
