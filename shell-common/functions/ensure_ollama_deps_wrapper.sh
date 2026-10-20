#!/bin/sh
# shell-common/functions/ensure_ollama_deps_wrapper.sh
# Wrapper function for ensure_ollama_deps executable
# Library function: no side effects, just delegates to external script

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

ensure_ollama_deps() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/ensure-ollama-deps.sh "$@"
}
