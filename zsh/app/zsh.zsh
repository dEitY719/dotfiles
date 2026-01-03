#!/bin/zsh

# zsh/app/zsh.zsh
# Zsh-specific shell integration functions
# POSIX-compatible functions are in shell-common/functions/zsh.sh

# ═══════════════════════════════════════════════════════════════
# Zsh-Specific Shell Switching
# ═══════════════════════════════════════════════════════════════

# Switch to zsh shell (zsh-specific, optimized for current shell)
zsh-switch() {
    if command -v zsh &>/dev/null; then
        ux_success "Switching to zsh..."
        exec zsh -i
    else
        ux_error "zsh is not installed. Run 'install-zsh' to install it."
        return 1
    fi
}

# Switch to bash shell (zsh-specific version)
bash-switch() {
    ux_success "Switching to bash..."
    exec bash -i
}

# Shorthand for shell switches (zsh-specific aliases)
alias zsh-to='zsh-switch'
alias bash-to='bash-switch'

# ═══════════════════════════════════════════════════════════════
# Zsh Quick Aliases
# ═══════════════════════════════════════════════════════════════

alias zsh-config='cat ~/.zshrc'                    # View zsh config
alias zsh-edit-quick='nano ~/.zshrc'               # Quick edit
alias zsh-info='zsh --version && echo && uname -a' # Zsh system info

# ═══════════════════════════════════════════════════════════════
# Zsh Help Registration
# ═══════════════════════════════════════════════════════════════

# Register help function description
# Only register if HELP_DESCRIPTIONS exists (loaded by my_help.zsh)
if [ -n "${HELP_DESCRIPTIONS+x}" ]; then
    HELP_DESCRIPTIONS[zsh-help]="Zsh shell management commands"
fi

# Note: In zsh, all functions are automatically available without explicit export
# (export -f is bash syntax and not needed in zsh)
# POSIX-compatible functions are auto-loaded from shell-common/functions/zsh.sh
