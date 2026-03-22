#!/bin/sh
# shell-common/functions/ollama_help.sh
# Ollama / LLM Model Management Help (Hybrid: WSL + Docker)

# Load UX library - use dynamic path detection with fallback
if ! type ux_header > /dev/null 2>&1; then
    ux_lib_path="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/ux_lib/ux_lib.sh"
    if [ -f "$ux_lib_path" ]; then
        . "$ux_lib_path" 2>/dev/null || true
    else
        # Fallback functions if UX library not found
        ux_header() { echo "=== $1 ==="; echo ""; }
        ux_section() { echo ""; echo "$1"; echo "---"; }
        ux_info() { echo "ℹ️  $1"; }
        ux_warning() { echo "⚠️  $1"; }
        ux_error() { echo "❌ $1" >&2; }
        ux_success() { echo "✅ $1"; }
        ux_bullet() { echo "  • $1"; }
        ux_table_row() { printf "  %-20s : %s\n" "$1" "$2"; }
    fi
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

        ux_section "Current Status"
        ux_error "WSL Ollama is not installed"
        ux_info "Currently using: Docker Ollama only"

        ux_section "Install WSL Ollama"
        ux_info "Run the installation command: install-ollama"

        ux_section "For Now"
        ux_info "Docker Ollama is running and ready to use."
        ux_info "View Docker commands with: ${UX_CODE}ollama-help --docker${UX_RESET}"
        return 0
    fi

    ux_header "Ollama Management (WSL Local)"

    ux_section "Model Management"
    ux_table_row "ollama-models" "List all installed models"
    ux_table_row "ollama-pull <name>" "Download a model (e.g., gpt-oss:20b)"
    ux_table_row "ollama-rm <name>" "Remove a model"
    ux_table_row "ollama-show <name>" "Display model configuration"

    ux_section "Model Usage"
    ux_table_row "ollama-run <model>" "Interactive chat session"
    ux_table_row "ollama-prompt <model> <txt>" "Single prompt execution"

    ux_section "Status & Information"
    ux_table_row "ollama-version" "Display Ollama version"
    ux_table_row "ollama-status" "Check service status and API health"

    ux_section "Server Management"
    ux_table_row "ollama-serve" "Start Ollama server (foreground)"
    ux_table_row "ollama-launch claude" "Connect Claude Code to Ollama"

    ux_section "System Management"
    ux_table_row "ollama-restart" "Restart systemd service and verify all checks"

    ux_section "Popular Models"
    ux_table_row "tinyllama:latest" "637 MB"  "Fast, lightweight"
    ux_table_row "gpt-oss:20b"      "13 GB"   "High-capability model"
    ux_table_row "mistral"          "4.1 GB"  "General-purpose"
    ux_table_row "neural-chat"      "3.8 GB"  "Chat-optimized"
    ux_table_row "bge-m3:latest"    "1.2 GB"  "Embeddings/search"

    ux_section "Quick Reference"
    ux_info "Storage:   ~/.ollama"
    ux_info "API:       http://127.0.0.1:11434"
    ux_info "Use ${UX_CODE}ollama-help --docker${UX_RESET} for Docker commands"
}

# Docker Ollama Help
_ollama_help_docker() {
    ux_header "Ollama Management (Docker Container)"

    ux_section "Model Management"
    ux_table_row "ollama-models [--docker]" "List all models"
    ux_table_row "ollama-pull --docker <name>" "Download a model"
    ux_table_row "ollama-rm --docker <name>" "Remove a model"
    ux_table_row "ollama-show --docker <name>" "Show model details"

    ux_section "Model Usage"
    ux_table_row "ollama-run --docker <model>" "Interactive chat"
    ux_table_row "ollama-prompt --docker <...>" "Single prompt"

    ux_section "Container Operations"
    ux_table_row "ollama-logs" "Follow container logs (real-time)"
    ux_table_row "ollama-stats" "Monitor resource usage"

    ux_section "Popular Models"
    ux_table_row "tinyllama:latest" "637 MB"  "Fast, lightweight"
    ux_table_row "gpt-oss:20b"      "13 GB"   "High-capability model"
    ux_table_row "mistral"          "4.1 GB"  "General-purpose"
    ux_table_row "neural-chat"      "3.8 GB"  "Chat-optimized"
    ux_table_row "bge-m3:latest"    "1.2 GB"  "Embeddings/search"

    ux_section "Quick Reference"
    ux_info "Storage:   /root/.ollama (container volume)"
    ux_info "API:       http://localhost:11434"
    ux_info "Use ${UX_CODE}ollama-help --local${UX_RESET} for WSL commands"
}

# Show current Ollama status
_ollama_help_status() {
    ux_header "Current Ollama Backend Status"

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
}

# Show usage information
_ollama_help_usage() {
    ux_header "ollama-help — Ollama Command Reference"

    ux_section "Usage"
    ux_info "ollama-help [OPTION]"

    ux_section "Options"
    ux_table_row "--auto" "Auto-detect backend (default)"
    ux_table_row "--docker" "Show Docker-specific commands"
    ux_table_row "--local" "Show WSL-specific commands"
    ux_table_row "--status" "Display current Ollama status"
    ux_table_row "-h, --help" "Show this help"
}

# Aliases defined in shell initialization (bashrc/zshrc) to avoid conflicts
