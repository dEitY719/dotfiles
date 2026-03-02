#!/bin/sh
# shell-common/functions/install_ollama_helper.sh
# Convenience wrapper for Ollama WSL installation

install_ollama() {
    if [ -n "${SHELL_COMMON}" ]; then
        bash "${SHELL_COMMON}/tools/custom/install-ollama.sh" "$@"
    else
        echo "Error: SHELL_COMMON not set" >&2
        return 1
    fi
}
