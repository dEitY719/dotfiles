#!/bin/bash
# shell-common/tools/custom/ollama_launch.sh
# ollama-launch — launch a tool (default: claude) wired to Ollama.
#
# PATH executable since #2195 (~/.local/bin/ollama-launch via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'ollama-launch'` resolve it too.
# functions/ollama_launcher.sh keeps the `ollama_launch` / `ollama-launch` names as a thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/tools/integrations/ollama.sh" || exit 1 # ollama_backend_*

main() {
    case "${1:-}" in
        -h|--help|help)
            ux_usage "ollama-launch" "[tool]" "Launch a tool (default: claude) wired to Ollama"
            return 0
            ;;
    esac

    local tool="${1:-claude}"

    local backend
    backend=$(ollama_backend_detect 2>/dev/null || echo "")
    if [ -z "$backend" ] || [ "$backend" = "unavailable" ]; then
        ux_error "Ollama is not available"
        ux_info "Make sure Ollama server is running first:"
        ux_info "  ollama-serve &"
        return 1
    fi
    
    ux_header "Launching $tool with Ollama..."
    echo ""
    ux_section "Backend Status"
    ollama_backend_status
    echo ""
    
    ux_section "Connecting to Ollama..."
    ux_info "Tool: $tool"
    ux_info "Command: ollama launch $tool"
    echo ""
    
    ollama launch "$tool"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
