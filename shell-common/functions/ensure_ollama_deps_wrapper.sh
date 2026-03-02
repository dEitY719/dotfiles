#!/bin/sh
# shell-common/functions/ensure_ollama_deps_wrapper.sh
# Wrapper function for ensure_ollama_deps executable
# Library function: no side effects, just delegates to external script

ensure_ollama_deps() {
    # Try SHELL_COMMON first, then fallback to default location
    local script_path="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/custom/ensure-ollama-deps.sh"

    if [ ! -f "$script_path" ]; then
        echo "Error: ensure-ollama-deps.sh not found at $script_path" >&2
        echo "Hint: Ensure SHELL_COMMON is set or dotfiles is at ~/dotfiles" >&2
        echo "      Current SHELL_COMMON=${SHELL_COMMON:-<not set>}" >&2
        return 1
    fi

    bash "$script_path" "$@"
}
