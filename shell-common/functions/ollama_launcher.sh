#!/bin/sh
# shell-common/functions/ollama_launcher.sh
# Convenience wrappers for Ollama launch and serve commands. Thin wrappers
# (#2195): the logic is tools/custom/ollama_serve.sh / ollama_launch.sh
# (~/.local/bin/ollama-serve, ollama-launch).

# Start Ollama server

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

ollama_serve() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/ollama_serve.sh "$@"
}

# Launch Claude Code or other tools with Ollama
ollama_launch() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/ollama_launch.sh "$@"
}
