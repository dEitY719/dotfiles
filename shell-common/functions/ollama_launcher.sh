#!/bin/sh
# shell-common/functions/ollama_launcher.sh
# Convenience wrappers for Ollama launch and serve commands

# Start Ollama server
ollama_serve() {
    local backend=$(ollama_backend_detect 2>/dev/null || echo "")
    
    if [[ -z "$backend" ]] || [[ "$backend" == "unavailable" ]]; then
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

# Launch Claude Code or other tools with Ollama
ollama_launch() {
    local tool="${1:-claude}"
    
    local backend=$(ollama_backend_detect 2>/dev/null || echo "")
    if [[ -z "$backend" ]] || [[ "$backend" == "unavailable" ]]; then
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
