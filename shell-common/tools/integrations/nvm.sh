#!/bin/sh
# shell-common/tools/integrations/nvm.sh
# NVM (Node Version Manager) - auto-source NVM in interactive shells only,
# expose `nvm-install` wrapper and `nvm-help` (defined in functions/nvm_help.sh).
#
# The interactive guard below skips the entire file (including the heavy
# `$NVM_DIR/nvm.sh` source) for non-interactive shells, so login costs stay zero
# unless DOTFILES_FORCE_INIT is set (used by bats/CI). See AGENTS.md.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# ========================================
# Load UX Library
# ========================================
if ! type ux_header >/dev/null 2>&1; then
    _nvm_dir="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
    . "${_nvm_dir}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
    unset _nvm_dir
fi

# ========================================
# NVM Auto-Source (interactive shells only)
# ========================================
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion

# ========================================
# NVM Install Wrapper
# ========================================
# Help: `nvm-help` (defined in shell-common/functions/nvm_help.sh)
nvm_install() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_nvm.sh" || return $?
    if type ux_info >/dev/null 2>&1; then
        ux_info "Open a new shell (or source your shell config) to pick up nvm."
    else
        echo "Open a new shell (or source your shell config) to pick up nvm."
    fi
}
alias nvm-install='nvm_install'
