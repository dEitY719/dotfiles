#!/bin/bash
# shell-common/tools/custom/ollama_serve.sh
# ollama-serve — start the WSL Ollama API server (127.0.0.1:11434).
#
# PATH executable since #2195 (~/.local/bin/ollama-serve via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'ollama-serve'` resolve it too.
# functions/ollama_launcher.sh keeps the `ollama_serve` / `ollama-serve` names as a thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/tools/integrations/ollama.sh" || exit 1 # ollama_backend_detect

main() {
    case "${1:-}" in
        -h|--help|help)
            ux_usage "ollama-serve" "" "Start the WSL Ollama API server (127.0.0.1:11434)"
            return 0
            ;;
    esac

    local backend
    backend=$(ollama_backend_detect 2>/dev/null || echo "")

    if [ -z "$backend" ] || [ "$backend" = "unavailable" ]; then
        ux_error "No Ollama backend available"
        ux_info "Install WSL Ollama: install-ollama"
        ux_info "Or ensure Docker Ollama is running"
        return 1
    fi
    
    case "$backend" in
        local)
            ux_header "Starting WSL Ollama Server..."
            ux_info "API will be available at: http://127.0.0.1:11434"
            ux_info "Press Ctrl+C to stop the server"
            echo ""
            ollama serve
            ;;
        docker)
            ux_error "Docker Ollama is already running"
            ux_info "To start WSL Ollama instead, install it first:"
            ux_info "  install-ollama"
            return 1
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
