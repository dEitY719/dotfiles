#!/bin/bash
# shell-common/tools/custom/install_ollama.sh
# WSL Environment: Ollama Binary Installation Script
# Handles installation, validation, and port conflict detection

set -e

# Load UX library - use absolute path
source /home/bwyoon/dotfiles/shell-common/tools/ux_lib/ux_lib.sh 2>/dev/null || {
    echo "Warning: UX library not found" >&2
}

main() {
    ux_header "Ollama WSL Installation Script"

    # Step 1: Pre-check - Is Ollama already installed?
    if command -v ollama &> /dev/null; then
        local version=$(ollama --version)
        ux_success "Ollama already installed: $version"
        return 0
    fi

    ux_section "Pre-installation Checks"

    # Check for required commands
    if ! command -v curl &> /dev/null; then
        ux_error "curl is required but not installed"
        return 1
    fi
    ux_success "curl found"

    # Check if running on Linux/WSL
    if [[ ! "$OSTYPE" == "linux-gnu"* ]]; then
        ux_error "This script is for Linux/WSL only"
        return 1
    fi
    ux_success "Running on Linux/WSL"

    # Step 2: Port conflict detection
    ux_section "Port Conflict Detection (11434)"
    if command -v lsof &> /dev/null; then
        if lsof -i :11434 &> /dev/null; then
            ux_error "Port 11434 is already in use!"
            local proc=$(lsof -i :11434 | tail -1)
            ux_info "Process: $proc"
            ux_info "Options:"
            ux_bullet "Stop Docker Ollama: docker stop ollama"
            ux_bullet "Use alternative port: export OLLAMA_HOST=127.0.0.1:11435"
            read -p "Continue anyway? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                ux_error "Installation cancelled"
                return 1
            fi
        else
            ux_success "Port 11434 is available"
        fi
    else
        ux_info "lsof not available, skipping port check"
    fi

    # Step 3: Installation
    ux_section "Installing Ollama from Official Script"
    ux_info "Downloading and running official installation script..."

    if curl -fsSL https://ollama.ai/install.sh | sh; then
        ux_success "Ollama installation completed"
    else
        ux_error "Installation script failed"
        return 1
    fi

    # Step 4: Post-installation validation
    ux_section "Post-Installation Validation"

    if ! command -v ollama &> /dev/null; then
        ux_error "Ollama not found in PATH after installation"
        return 1
    fi

    local version=$(ollama --version)
    ux_success "Ollama installed: $version"

    # Step 5: Environment configuration
    ux_section "Environment Configuration"

    # Set recommended environment variables
    export OLLAMA_NUM_CTX=65536
    export OLLAMA_NUM_GPU=-1
    export OLLAMA_KEEP_ALIVE=5m

    ux_info "Recommended environment variables:"
    ux_bullet "OLLAMA_NUM_CTX=65536 (64K context length)"
    ux_bullet "OLLAMA_NUM_GPU=-1 (GPU auto-detect)"
    ux_bullet "OLLAMA_KEEP_ALIVE=5m (Memory efficiency)"

    # Suggestion to add to shell profile
    ux_section "Next Steps"
    ux_bullet "Add to ~/.bashrc or ~/.zshrc:"
    echo ""
    cat << 'EOF'
export OLLAMA_NUM_CTX=65536
export OLLAMA_NUM_GPU=-1
export OLLAMA_KEEP_ALIVE=5m
export DOTFILES_OLLAMA_BACKEND=auto
EOF
    echo ""

    ux_bullet "Start Ollama service:"
    ux_info "  ollama serve"

    ux_bullet "Test installation:"
    ux_info "  ollama_status  # or: ollama list"

    ux_bullet "Download models:"
    ux_info "  ollama_pull gpt-oss:20b"

    ux_success "Installation complete! Ollama is ready to use."
}

# Direct execution guard (script 직접 실행 시에만 동작)
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
