#!/bin/sh
# shell-common/functions/ensure_ollama_deps_wrapper.sh
# Wrapper function for ensure_ollama_deps executable
# Library function: no side effects, just delegates to external script

ensure_ollama_deps() {
    if [ -n "${SHELL_COMMON}" ]; then
        bash "${SHELL_COMMON}/tools/custom/ensure-ollama-deps.sh" "$@"
    else
        echo "Error: SHELL_COMMON not set" >&2
        return 1
    fi
}
