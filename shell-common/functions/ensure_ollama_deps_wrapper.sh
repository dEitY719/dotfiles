#!/bin/sh
# shell-common/functions/ensure_ollama_deps_wrapper.sh
# Wrapper function for ensure_ollama_deps executable
# Library function: no side effects, just delegates to external script

ensure_ollama_deps() {
    bash /home/bwyoon/dotfiles/shell-common/tools/custom/ensure_ollama_deps.sh "$@"
}
