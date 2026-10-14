#!/bin/sh
# shell-common/functions/install_ollama_helper.sh
# Convenience wrapper for Ollama WSL installation

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

install_ollama() {
    local _exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/install-ollama.sh
    "$_exe" "$@"
}
