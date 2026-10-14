#!/bin/sh
# shell-common/functions/shell_switch.sh
# SSOT for shell switching functions (POSIX-compatible)
# Previously duplicated in zsh/app/zsh.zsh and tools/integrations/zsh.sh

# Switch to zsh shell

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

zsh_switch() {
    if command -v zsh >/dev/null 2>&1; then
        ux_success "Switching to zsh..."
        exec zsh -i
    else
        ux_error "zsh is not installed. Run 'install-zsh' to install it."
        return 1
    fi
}

# Switch to bash shell
bash_switch() {
    if command -v bash >/dev/null 2>&1; then
        ux_success "Switching to bash..."
        exec bash -i
    else
        ux_error "bash is not installed."
        return 1
    fi
}

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func zsh_switch "Switch the login shell to zsh"
_register_func bash_switch "Switch the login shell to bash"
