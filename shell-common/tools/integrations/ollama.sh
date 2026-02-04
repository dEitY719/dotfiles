#!/bin/sh
# shell-common/tools/integrations/ollama.sh
# Ollama Hybrid Integration: WSL + Docker Seamless Management
# Provides unified interface for both WSL and Docker Ollama environments

# Load UX library - use absolute path
source /home/bwyoon/dotfiles/shell-common/tools/ux_lib/ux_lib.sh 2>/dev/null || {
    echo "Warning: UX library not found" >&2
}

# ═══════════════════════════════════════════════════════════════════════════
# CORE: Backend Detection and Command Execution
# ═══════════════════════════════════════════════════════════════════════════

# Detect available backend (local or docker)
# Returns: local | docker | unavailable
ollama_backend_detect() {
    local forced_backend="${DOTFILES_OLLAMA_BACKEND:-}"

    # 1. Check for explicit environment variable override
    if [[ "$forced_backend" == "local" || "$forced_backend" == "docker" ]]; then
        echo "$forced_backend"
        return 0
    fi

    # 2. Check for local ollama binary
    if command -v ollama &> /dev/null; then
        echo "local"
        return 0
    fi

    # 3. Check for docker container
    local container_name="${DOTFILES_OLLAMA_DOCKER_CONTAINER:-ollama}"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        echo "docker"
        return 0
    fi

    # 4. Not available
    echo "unavailable"
    return 1
}

# Get current backend status with details
ollama_backend_status() {
    local backend=$(ollama_backend_detect)
    local status

    case "$backend" in
        local)
            local version=$(ollama --version 2>/dev/null || echo "unknown")
            ux_success "Backend: LOCAL (WSL)"
            ux_info "Version: $version"
            ux_info "Host: 127.0.0.1:11434 (default)"
            ;;
        docker)
            ux_success "Backend: DOCKER"
            local container_name="${DOTFILES_OLLAMA_DOCKER_CONTAINER:-ollama}"
            ux_info "Container: $container_name"
            ux_info "Host: http://$container_name:11434 (internal)"
            ;;
        unavailable)
            ux_error "Backend: UNAVAILABLE"
            ux_info "Neither WSL nor Docker Ollama is available"
            return 1
            ;;
    esac
}

# Execute ollama command with automatic backend selection
# Usage: ollama_cmd [--docker|--local|--auto] <ollama_args>
ollama_cmd() {
    local backend_override=""
    local args=()

    # Parse backend override flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --docker)
                backend_override="docker"
                shift
                ;;
            --local)
                backend_override="local"
                shift
                ;;
            --auto)
                backend_override=""
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Determine backend
    local backend
    if [[ -n "$backend_override" ]]; then
        backend="$backend_override"
    else
        backend=$(ollama_backend_detect)
    fi

    # Execute command
    case "$backend" in
        local)
            command ollama "${args[@]}"
            ;;
        docker)
            local container_name="${DOTFILES_OLLAMA_DOCKER_CONTAINER:-ollama}"
            docker exec "$container_name" ollama "${args[@]}"
            ;;
        unavailable)
            ux_error "Ollama is not available (neither local nor Docker)"
            return 1
            ;;
    esac
}

# Get API base URL for current backend
ollama_api_base_url() {
    local backend=$(ollama_backend_detect)

    case "$backend" in
        local)
            echo "${OLLAMA_HOST:-127.0.0.1:11434}"
            ;;
        docker)
            local container_name="${DOTFILES_OLLAMA_DOCKER_CONTAINER:-ollama}"
            echo "http://$container_name:11434"
            ;;
        unavailable)
            ux_error "Ollama backend not available"
            return 1
            ;;
    esac
}

# Normalize model name (gpt-oss-20b → gpt-oss:20b)
ollama_normalize_model_name() {
    local model="$1"
    # Replace hyphen before numbers with colon (if looks like version)
    echo "$model" | sed 's/-\([0-9]\)/:\1/'
}

# ═══════════════════════════════════════════════════════════════════════════
# P0: Basic Management Functions (Required)
# ═══════════════════════════════════════════════════════════════════════════

# Get Ollama version
ollama_version() {
    local backend=$(ollama_backend_detect)
    [[ "$backend" == "unavailable" ]] && {
        ux_error "Ollama not available"
        return 1
    }
    ollama_cmd --auto version 2>/dev/null || ollama_cmd --auto --version
}

# Check environment variables configuration
ollama_status_env() {
    ux_header "Ollama Environment Configuration"
    echo ""

    ux_section "Environment Variables"
    ux_bullet "OLLAMA_NUM_CTX=$OLLAMA_NUM_CTX (context length)"
    ux_bullet "OLLAMA_NUM_GPU=$OLLAMA_NUM_GPU (GPU selection)"
    ux_bullet "OLLAMA_KEEP_ALIVE=$OLLAMA_KEEP_ALIVE (cache timeout)"
    ux_bullet "DOTFILES_OLLAMA_BACKEND=$DOTFILES_OLLAMA_BACKEND (backend mode)"
    echo ""

    ux_section "Configuration Source"
    ux_info "File: ~/dotfiles/shell-common/env/ollama.sh"
    ux_info "Auto-loaded: Yes (via shell initialization)"
    echo ""

    ux_section "Customization"
    ux_info "To change settings:"
    ux_info "  1. Edit: ~/dotfiles/shell-common/env/ollama.sh"
    ux_info "  2. Reload shell: exec \$SHELL"
    echo ""
}

# Get Ollama status
ollama_status() {
    ux_header "Ollama Status"

    local backend=$(ollama_backend_detect)
    if [[ "$backend" == "unavailable" ]]; then
        ux_error "Ollama is not available"
        echo ""
        echo "Install options:"
        echo "  1. WSL: bash shell-common/tools/custom/install_ollama.sh"
        echo "  2. Docker: docker start ollama"
        return 1
    fi

    ollama_backend_status
    echo ""

    # Check if service is responding
    local api_url=$(ollama_api_base_url)
    ux_section "Service Check"
    if curl -s "$api_url/api/tags" > /dev/null 2>&1; then
        ux_success "API responding at $api_url"
    else
        ux_error "API not responding at $api_url"
        return 1
    fi
}

# List installed models
ollama_models() {
    local backend_arg=""

    # Check for explicit backend flag
    if [[ "$1" == "--docker" || "$1" == "--local" || "$1" == "--auto" ]]; then
        backend_arg="$1"
    fi

    ollama_cmd $backend_arg list
}

# Pull a model
ollama_pull() {
    local model="${1:?Model name required}"

    # Normalize model name if needed
    model=$(ollama_normalize_model_name "$model")

    ux_info "Pulling model: $model"
    ollama_cmd --auto pull "$model"
}

# Remove a model
ollama_rm() {
    local model="${1:?Model name required}"
    model=$(ollama_normalize_model_name "$model")

    ux_info "Removing model: $model"
    ollama_cmd --auto rm "$model"
}

# Show model details
ollama_show() {
    local model="${1:?Model name required}"
    model=$(ollama_normalize_model_name "$model")

    ollama_cmd --auto show "$model"
}

# Run a model (interactive)
ollama_run() {
    local model="${1:?Model name required}"
    model=$(ollama_normalize_model_name "$model")

    ux_info "Starting interactive chat with: $model"
    ollama_cmd --auto run "$model"
}

# ═══════════════════════════════════════════════════════════════════════════
# P1: Advanced Functions (Optional)
# ═══════════════════════════════════════════════════════════════════════════

# Show Docker Ollama logs (docker only)
ollama_logs() {
    local container_name="${DOTFILES_OLLAMA_DOCKER_CONTAINER:-ollama}"
    docker logs "$@" "$container_name"
}

# Show Docker Ollama resource stats (docker only)
ollama_stats() {
    local container_name="${DOTFILES_OLLAMA_DOCKER_CONTAINER:-ollama}"
    docker stats "$container_name"
}

# Run single prompt (non-interactive)
ollama_prompt() {
    local model="${1:?Model name required}"
    local prompt="${2:?Prompt text required}"

    model=$(ollama_normalize_model_name "$model")

    ollama_cmd --auto run "$model" "$prompt"
}

# ═══════════════════════════════════════════════════════════════════════════
# Functions are automatically available after sourcing in both bash and zsh
# Note: export -f is bash-only and not supported in zsh
# ═══════════════════════════════════════════════════════════════════════════
