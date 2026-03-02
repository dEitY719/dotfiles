#!/bin/sh
# shell-common/functions/install_ollama_helper.sh
# Convenience wrapper for Ollama WSL installation

install_ollama() {
    # Try SHELL_COMMON first, then fallback to default location
    local script_path="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/custom/install-ollama.sh"

    if [ ! -f "$script_path" ]; then
        echo "Error: install-ollama.sh not found at $script_path" >&2
        echo "Hint: Ensure SHELL_COMMON is set or dotfiles is at ~/dotfiles" >&2
        echo "      Current SHELL_COMMON=${SHELL_COMMON:-<not set>}" >&2
        return 1
    fi

    bash "$script_path" "$@"
}
