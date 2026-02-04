#!/bin/sh
# shell-common/functions/ollama_help.sh
# Ollama / LLM Model Management Help (Hybrid: WSL + Docker)
# Follows UX_GUIDELINES.md for consistent, semantic output

# Load UX library - absolute path (most reliable)
if ! declare -f ux_header > /dev/null 2>&1; then
    source /home/bwyoon/dotfiles/shell-common/tools/ux_lib/ux_lib.sh 2>/dev/null || true
fi

# Main help function with auto-detection
ollama_help() {
    local mode="${1:-auto}"

    case "$mode" in
        --docker)
            _ollama_help_docker
            ;;
        --local)
            _ollama_help_local
            ;;
        --status | --backend)
            _ollama_help_status
            ;;
        --auto | auto | "")
            _ollama_help_auto
            ;;
        --help | -h)
            _ollama_help_usage
            ;;
        *)
            ux_error "Unknown option: $mode"
            _ollama_help_usage
            return 1
            ;;
    esac
}

# Auto-detect and show appropriate help
_ollama_help_auto() {
    if command -v ollama_backend_detect &> /dev/null; then
        local backend=$(ollama_backend_detect 2>/dev/null || echo "docker")
        if [[ "$backend" == "local" ]]; then
            _ollama_help_local
        else
            _ollama_help_docker
        fi
    else
        _ollama_help_docker
    fi
}

# WSL Local Ollama Help
_ollama_help_local() {
    # Check if local ollama is available
    if ! command -v ollama &> /dev/null; then
        ux_header "WSL Ollama — Not Installed"
        echo ""
        ux_section "Current Status"
        ux_error "WSL Ollama is not installed"
        ux_info "Currently using: Docker Ollama only"
        echo ""

        ux_section "Install WSL Ollama"
        ux_info "Run the installation command:"
        ux_info "  install-ollama"
        echo ""

        ux_section "For Now"
        ux_info "Docker Ollama is running and ready to use."
        ux_info "View Docker commands with: ${UX_CODE}ollama-help --docker${UX_RESET}"
        echo ""
        return 0
    fi

    ux_header "Ollama Management (WSL Local)"

    ux_section "Model Management"
    ux_bullet "ollama-models       — List all installed models"
    ux_bullet "ollama-pull <name>  — Download a model (e.g., gpt-oss:20b)"
    ux_bullet "ollama-rm <name>    — Remove a model"
    ux_bullet "ollama-show <name>  — Display model configuration"
    echo ""

    ux_section "Model Usage"
    ux_bullet "ollama-run <model>          — Interactive chat session"
    ux_bullet "ollama-prompt <model> <txt> — Single prompt execution"
    echo ""

    ux_section "Status & Information"
    ux_bullet "ollama-version — Display Ollama version"
    ux_bullet "ollama-status  — Check service status and API health"
    echo ""

    ux_section "Server Management"
    ux_bullet "ollama-serve         — Start Ollama server (foreground)"
    ux_bullet "ollama-launch claude — Connect Claude Code to Ollama"
    echo ""

    ux_section "System Management"
    ux_bullet "ollama-restart — Restart systemd service and verify all checks"
    echo ""

    ux_section "Popular Models"
    ux_table_row "tinyllama:latest" "637 MB"  "Fast, lightweight"
    ux_table_row "gpt-oss:20b"      "13 GB"   "High-capability model"
    ux_table_row "mistral"          "4.1 GB"  "General-purpose"
    ux_table_row "neural-chat"      "3.8 GB"  "Chat-optimized"
    ux_table_row "bge-m3:latest"    "1.2 GB"  "Embeddings/search"
    echo ""

    ux_section "Examples"
    ux_numbered "1" "Start Ollama server:"
    ux_info "   ollama-serve"
    echo ""
    ux_numbered "2" "Connect Claude Code (in another terminal):"
    ux_info "   ollama-launch claude"
    echo ""
    ux_numbered "3" "Download and use a model:"
    ux_info "   ollama-pull gpt-oss:20b"
    ux_info "   ollama-pull glm-4.7-flash"
    echo ""
    ux_info "   ollama-run gpt-oss:20b"
    ux_info "   ollama-run glm-4.7-flash"
    echo ""
    ux_numbered "4" "Single prompt:"
    ux_info "   ollama-prompt gpt-oss:20b 'Explain quantum computing'"
    echo ""

    ux_section "Quick Reference"
    ux_info "Storage:   ~/.ollama"
    ux_info "API:       http://127.0.0.1:11434"
    ux_info "Use ${UX_CODE}ollama-help --docker${UX_RESET} for Docker commands"
    echo ""
}

# Docker Ollama Help
_ollama_help_docker() {
    ux_header "Ollama Management (Docker Container)"

    ux_section "Model Management"
    ux_bullet "ollama-models [--docker]       — List all models"
    ux_bullet "ollama-pull --docker <name>    — Download a model"
    ux_bullet "ollama-rm --docker <name>      — Remove a model"
    ux_bullet "ollama-show --docker <name>    — Show model details"
    echo ""

    ux_section "Model Usage"
    ux_bullet "ollama-run --docker <model>    — Interactive chat"
    ux_bullet "ollama-prompt --docker <...>   — Single prompt"
    echo ""

    ux_section "Container Operations"
    ux_bullet "ollama-logs       — Follow container logs (real-time)"
    ux_bullet "ollama-stats      — Monitor resource usage"
    ux_bullet "docker logs -f ollama   — Raw Docker logs"
    echo ""

    ux_section "Popular Models"
    ux_table_row "tinyllama:latest" "637 MB"  "Fast, lightweight"
    ux_table_row "gpt-oss:20b"      "13 GB"   "High-capability model"
    ux_table_row "mistral"          "4.1 GB"  "General-purpose"
    ux_table_row "neural-chat"      "3.8 GB"  "Chat-optimized"
    ux_table_row "bge-m3:latest"    "1.2 GB"  "Embeddings/search"
    echo ""

    ux_section "Examples"
    ux_numbered "1" "List models:"
    ux_info "   ollama-models --docker"
    echo ""
    ux_numbered "2" "Download and use:"
    ux_info "   ollama-pull --docker mistral"
    ux_info "   ollama-run --docker mistral"
    echo ""
    ux_numbered "3" "Interactive chat:"
    ux_info "   docker exec -it ollama ollama run tinyllama"
    echo ""

    ux_section "Quick Reference"
    ux_info "Storage:   /root/.ollama (container volume)"
    ux_info "API:       http://localhost:11434"
    ux_info "Use ${UX_CODE}ollama-help --local${UX_RESET} for WSL commands"
    echo ""
}

# Show current Ollama status
_ollama_help_status() {
    ux_header "Current Ollama Backend Status"
    echo ""

    if command -v ollama_backend_status &> /dev/null; then
        ollama_backend_status
    else
        if command -v ollama &> /dev/null; then
            ux_success "Backend: LOCAL (WSL)"
            ux_info "Version: $(ollama --version 2>/dev/null || echo 'unknown')"
            ux_info "API: http://127.0.0.1:11434"
        elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"; then
            ux_success "Backend: DOCKER"
            ux_info "Container: ollama (running)"
            ux_info "API: http://ollama:11434"
        else
            ux_error "No Ollama backend available"
            ux_info "Install options:"
            ux_bullet "WSL: bash ~/dotfiles/shell-common/tools/custom/install_ollama.sh"
            ux_bullet "Docker: docker start ollama"
        fi
    fi
    echo ""
}

# Show usage information
_ollama_help_usage() {
    ux_header "ollama-help — Ollama Command Reference"
    echo ""

    ux_section "Usage"
    ux_info "ollama-help [OPTION]"
    echo ""

    ux_section "Options"
    ux_bullet "--auto     Auto-detect backend (default when no option given)"
    ux_bullet "--docker   Show Docker-specific commands"
    ux_bullet "--local    Show WSL-specific commands"
    ux_bullet "--status   Display current Ollama status"
    ux_bullet "-h, --help Show this help"
    echo ""

    ux_section "Examples"
    ux_info "ollama-help           # Auto-detect (recommended)"
    ux_info "ollama-help --docker  # Docker-specific help"
    ux_info "ollama-help --local   # WSL-specific help"
    ux_info "ollama-help --status  # Show current status"
    echo ""
}

# Aliases defined in shell initialization (bashrc/zshrc) to avoid conflicts
