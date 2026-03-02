#!/bin/bash
# shell-common/tools/custom/install_ollama.sh
# WSL Environment: Ollama Binary Installation Script
# Supports: online installation (download from GitHub) & offline installation (local file)
# Handles installation, validation, and port conflict detection

set -e

# Load UX library - use dynamic path detection
if [ -n "${SHELL_COMMON}" ] && [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null || {
        echo "Warning: UX library not found" >&2
    }
else
    echo "Warning: UX library not found" >&2
fi

main() {
    local offline_file="${1:-}"

    # Check for --offline flag or auto-detect ollama*.tar.zst in current directory
    if [ "$offline_file" = "--offline" ] && [ -n "$2" ]; then
        offline_file="$2"
    elif [ -z "$offline_file" ]; then
        # Auto-detect ollama tar.zst in current directory
        if ls ollama*.tar.zst 1> /dev/null 2>&1; then
            offline_file=$(ls ollama*.tar.zst 2>/dev/null | head -1)
            ux_info "Detected local installation file: $offline_file"
        fi
    fi

    ux_header "Ollama WSL Installation Script"

    # Show mode
    if [ -n "$offline_file" ]; then
        echo ""
        ux_section "Installation Mode"
        ux_info "Mode: OFFLINE (using local file)"
        ux_info "File: $offline_file"
    fi

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

    # Check for zstd (required by Ollama installation)
    if ! command -v zstd &> /dev/null; then
        ux_error "zstd is required but not installed"
        echo ""
        ux_section "Install zstd"
        ux_info "Run this command first:"
        ux_info "  ensure-ollama-deps"
        echo ""
        ux_info "Or install manually:"
        ux_info "  - Debian/Ubuntu: sudo apt-get install zstd"
        ux_info "  - RHEL/CentOS/Fedora: sudo dnf install zstd"
        ux_info "  - Arch: sudo pacman -S zstd"
        echo ""
        return 1
    fi
    ux_success "zstd found"

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

    # Step 2.5: Network connectivity check
    ux_section "Network Connectivity Check"
    local net_check=$(mktemp)
    curl -I -m 5 https://ollama.com > "$net_check" 2>&1
    local curl_exit=$?

    if [ $curl_exit -ne 0 ] && grep -q "Connection reset by peer\|Recv failure\|Failed to connect\|timeout" "$net_check" 2>/dev/null; then
        ux_error "Cannot reach ollama.com (required for installation)"
        ux_info "This is needed to download Ollama binary from:"
        ux_info "  https://ollama.com/install.sh"
        echo ""
        ux_section "Diagnostics"
        grep "Connection reset\|error\|Failed" "$net_check" | sed 's/^/  /'
        echo ""
        ux_section "Possible Causes"
        ux_bullet "Company firewall/proxy blocking GitHub"
        ux_bullet "Network policy restriction"
        echo ""
        read -p "Continue installation anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            ux_error "Installation cancelled (network issue)"
            rm -f "$net_check"
            return 1
        fi
    elif grep -q "200\|301\|302" "$net_check" 2>/dev/null; then
        ux_success "ollama.com connectivity verified"
    else
        ux_info "Network check inconclusive, proceeding with installation..."
    fi
    rm -f "$net_check"

    # Step 3: Installation
    ux_section "Installing Ollama"

    local install_log=$(mktemp)

    if [ -n "$offline_file" ]; then
        # OFFLINE MODE: Install from local tar file
        if [ ! -f "$offline_file" ]; then
            ux_error "File not found: $offline_file"
            return 1
        fi

        ux_info "Installing from local file: $offline_file"
        echo ""

        # Extract tar file (zstd compressed)
        if sudo tar -xf "$offline_file" --zstd -C /usr/local 2>"$install_log"; then
            ux_success "Ollama installation completed from local file"
            rm -f "$install_log"
        else
            ux_error "Failed to extract Ollama archive"
            tail -5 "$install_log" | sed 's/^/  /'
            rm -f "$install_log"
            return 1
        fi
    else
        # ONLINE MODE: Download from official Ollama site via official script
        ux_info "Downloading and running official installation script..."
        echo ""

        # Attempt installation and capture error output
        if curl -fsSL https://ollama.com/install.sh 2>"$install_log" | sh 2>>"$install_log"; then
            ux_success "Ollama installation completed"
            rm -f "$install_log"
        else
        local exit_code=$?
        ux_error "Installation script failed (exit code: $exit_code)"
        echo ""

        # Check for network/connectivity errors
        if grep -q "Connection reset by peer\|Recv failure\|Failed to connect\|Network is unreachable" "$install_log" 2>/dev/null; then
            ux_section "Network Connectivity Issue"
            ux_error "Cannot reach ollama.com to download Ollama binary"
            echo ""
            ux_section "Possible Causes"
            ux_bullet "Company firewall/proxy blocking ollama.com"
            ux_bullet "ISP/Network policy restriction"
            ux_bullet "DNS resolution failure"
            echo ""
            ux_section "Solutions"
            echo ""
            ux_numbered "1" "Request ollama.com access from IT (Recommended):"
            ux_info "   Request access to:"
            ux_info "   • Domain: ollama.com:443 (HTTPS)"
            ux_info "   • URL: https://ollama.com/install.sh"
            ux_info "   Then retry: install-ollama"
            echo ""
            ux_numbered "2" "Manual Offline Installation (Step-by-Step):"
            echo ""
            ux_section "Step 1: Download on Accessible Network"
            ux_info "On a PC with internet access (home, cafe, different network):"
            ux_info ""
            ux_info "Run this command:"
            echo "  curl -L -O https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst"
            echo ""
            ux_info "File will be saved as: ollama-linux-amd64.tar.zst"
            ux_info "Size: ~1.7 GB (takes ~15 minutes on 2 MB/s connection)"
            echo ""
            ux_section "Step 2: Transfer to This PC"
            ux_info "Move ollama-linux-amd64.tar.zst to this computer using:"
            ux_bullet "USB drive (easiest)"
            ux_bullet "Cloud storage (Google Drive, Dropbox, OneDrive)"
            ux_bullet "Network transfer (scp, rsync if available)"
            echo ""
            ux_section "Step 3: Place File in Home Directory"
            ux_info "Suggested location: ~/download/"
            ux_info ""
            ux_info "Commands:"
            echo "  mkdir -p ~/download"
            echo "  # Copy or move ollama-linux-amd64.tar.zst to ~/download/"
            echo ""
            ux_section "Step 4: Run Installation Script Again"
            ux_info "From the directory with the file:"
            echo "  cd ~/download"
            echo "  install-ollama"
            echo ""
            ux_info "The script will automatically detect and use the file!"
            ux_info "Or specify explicitly:"
            echo "  install-ollama /path/to/ollama-linux-amd64.tar.zst"
            echo ""
            ux_numbered "3" "Diagnose your network connection:"
            ux_info "   curl -v https://github.com"
            ux_info "   (look for 'Connection reset' or 'error' messages)"
            echo ""
        else
            # Generic installation error with log snippet
            ux_section "Installation Error Details"
            if [ -s "$install_log" ]; then
                tail -5 "$install_log" | sed 's/^/  /'
            else
                ux_info "No error output captured"
            fi
            echo ""
        fi

        rm -f "$install_log"
        return 1
        fi
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

    ux_success "Environment variables automatically configured!"
    ux_info "Source: ~/dotfiles/shell-common/env/ollama.sh"
    echo ""
    ux_section "Settings (Currently Active)"
    ux_bullet "OLLAMA_NUM_CTX=65536 (64K context length)"
    ux_bullet "OLLAMA_NUM_GPU=-1 (GPU auto-detect)"
    ux_bullet "OLLAMA_KEEP_ALIVE=5m (Memory efficiency)"
    ux_bullet "DOTFILES_OLLAMA_BACKEND=auto (auto-detect local/docker)"
    echo ""
    ux_info "These are automatically loaded in new shell sessions."
    ux_info "To customize: edit ~/dotfiles/shell-common/env/ollama.sh"
    echo ""

    # Next steps
    ux_section "Next Steps"
    ux_numbered "1" "Start Ollama service:"
    ux_info "   ollama serve"
    echo ""
    ux_numbered "2" "Test installation (new terminal):"
    ux_info "   ollama-status"
    ux_info "   ollama-models"
    echo ""
    ux_numbered "3" "Download a model:"
    ux_info "   ollama-pull gpt-oss:20b"
    ux_info "   ollama-pull glm-4.7-flash"
    echo ""
    ux_numbered "4" "Connect Claude Code:"
    ux_info "   ollama-launch claude"
    echo ""

    ux_success "Installation complete! Ollama is ready to use."
}

# Direct execution guard (script 직접 실행 시에만 동작)
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
