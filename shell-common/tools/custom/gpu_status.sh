#!/bin/bash
# gpu_status.sh - WSL2 환경 최적화 GPU 상태 모니터링
# 목적: WSL2 특성상 컨테이너 내 nvidia-smi 사용 불가를 해결하고
#      Ollama의 실제 GPU 사용 현황을 정확히 진단

set -e

# Source the UX library

source "$(dirname "$0")/../../bash/ux_lib/ux_lib.bash"

ux_header "GPU Status Monitor (for WSL2)"
echo ""

# =============================================================================
# [섹션 1/5] WSL2 호스트 GPU 하드웨어
# =============================================================================
ux_step "1/5" "Checking WSL2 Host GPU Hardware"

if [ -x /usr/lib/wsl/lib/nvidia-smi ]; then
    # nvidia-smi will add units like "MiB" automatically
    GPU_INFO=$(/usr/lib/wsl/lib/nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.free,memory.used --format=csv,noheader 2>/dev/null)

    if [ -n "$GPU_INFO" ]; then
        ux_success "Host GPU detected successfully."
        echo ""
        # ux_table_row is not suitable for this 6-column layout, so we format manually
        printf "  ${UX_BOLD}%-9s │ %-30s │ %-8s │ %-10s │ %-9s │ %s${UX_RESET}\n" "Index" "GPU Name" "Driver" "Total VRAM" "Free VRAM" "Used VRAM"
        printf "  ${UX_MUTED}──────────────────────────────────────────────────────────────────────────────────────────────────${UX_RESET}\n"
        echo "$GPU_INFO" | while IFS=, read -r index name driver total free used; do
            printf "  %-9s │ %-30s │ %-8s │ %-10s │ %-9s │ %s\n" \
                "$index" "$(echo $name | cut -c1-30)" "$driver" "$total" "$free" "$used"
        done
        echo ""
    else
        ux_error "Failed to query GPU information from host nvidia-smi."
        echo ""
    fi
else
    ux_warning "Host nvidia-smi not found at /usr/lib/wsl/lib/nvidia-smi."
    ux_info "This is the expected path for nvidia-smi in a WSL2 environment."
    echo ""
fi

# =============================================================================
# [섹션 2/5] Docker GPU 설정
# =============================================================================
ux_step "2/5" "Checking Docker GPU Settings for 'ollama' container"

if ! docker inspect ollama > /dev/null 2>&1; then
    ux_error "Ollama container is not running. Start it with 'docker compose up -d'."
else
    GPU_CONFIG=$(docker inspect ollama --format '{{json .HostConfig.DeviceRequests}}' 2>/dev/null || echo "[]")
    if echo "$GPU_CONFIG" | grep -q '"Driver":"nvidia"'; then
        ux_success "Ollama container is configured to use GPU."
        if command -v jq &> /dev/null; then
            GPU_COUNT=$(echo "$GPU_CONFIG" | jq -r '.[0].Count // -1' 2>/dev/null || echo "-1")
            [ "$GPU_COUNT" = "-1" ] && GPU_COUNT="all"
            ux_bullet "Driver: nvidia"
            ux_bullet "Count: $GPU_COUNT"
            ux_bullet "Capabilities: gpu"
        else
            ux_bullet "Driver: nvidia (jq not found for more details)"
        fi
    else
        ux_warning "Ollama container is not configured to use GPU."
        ux_info "Check the deploy.resources.reservations.devices section in your docker-compose.yml."
    fi
fi
echo ""

# =============================================================================
# [섹션 3/5] Ollama GPU 사용 현황 (핵심!)
# =============================================================================
ux_step "3/5" "Analyzing Ollama GPU Usage from container logs"

LAYERS_OFFLOADED="" # Define scope for section 5
LATEST_OFFLOAD=""

if ! docker logs ollama > /dev/null 2>&1; then
    ux_error "Cannot read logs from Ollama container."
else
    GPU_MEMORY_LOG=$(docker logs ollama 2>&1 | grep "gpu memory" | tail -1)
    if [ -n "$GPU_MEMORY_LOG" ]; then
        ux_success "Ollama has detected GPU memory."
        GPU_AVAILABLE=$(echo "$GPU_MEMORY_LOG" | grep -oP 'available="\K[^"]+' || echo "?")
        GPU_FREE=$(echo "$GPU_MEMORY_LOG" | grep -oP 'free="\K[^"]+' || echo "?")
        ux_bullet "Available VRAM from log: $GPU_AVAILABLE"
        ux_bullet "Free VRAM from log:      $GPU_FREE"
    else
        ux_warning "No GPU memory detection log found."
        ux_info "Ollama may not have loaded a model into the GPU yet."
    fi

    LATEST_OFFLOAD=$(docker logs ollama 2>&1 | grep "offloaded.*layers to GPU" | tail -1)
    if [ -n "$LATEST_OFFLOAD" ]; then
        LAYERS_OFFLOADED=$(echo "$LATEST_OFFLOAD" | grep -oP 'offloaded \K\d+/\d+')
        if [[ "$LAYERS_OFFLOADED" == "0/"* ]]; then
            ux_error "GPU layer offload failed! ($LAYERS_OFFLOADED)"
            ux_warning "Ollama is running in CPU-only mode, which will be very slow."
        else
            ux_success "GPU layer offload successful ($LAYERS_OFFLOADED)."
        fi
    else
        ux_warning "No layer offload log found."
        ux_info "Try running a model through Ollama to trigger offloading."
    fi
fi
echo ""

# =============================================================================
# [섹션 4/5] Ollama 환경변수
# =============================================================================
ux_step "4/5" "Checking Ollama Environment Variables"

if ! docker exec ollama env > /dev/null 2>&1; then
    ux_warning "Cannot access Ollama container to check environment variables."
else
    OLLAMA_ENVS=$(docker exec ollama env 2>/dev/null | grep -E "OLLAMA_|CUDA_" | sort)
    if [ -n "$OLLAMA_ENVS" ]; then
        ux_info "Found relevant environment variables:"
        echo "${UX_MUTED}"
        echo "$OLLAMA_ENVS" | sed 's/^/  /'
        echo "${UX_RESET}"
        
        if ! echo "$OLLAMA_ENVS" | grep -q "OLLAMA_GPU_OVERHEAD"; then
            ux_warning "OLLAMA_GPU_OVERHEAD is not set. (Recommended)"
        fi
        if ! echo "$OLLAMA_ENVS" | grep -q "OLLAMA_NUM_GPU"; then
            ux_warning "OLLAMA_NUM_GPU is not set. (Set if offloading fails)"
        fi
    else
        ux_info "No specific OLLAMA_* or CUDA_* environment variables set (using defaults)."
    fi
fi
echo ""


# =============================================================================
# [섹션 5/5] 성능 권장사항
# =============================================================================
ux_step "5/5" "Performance Recommendations"

if [[ -n "$LAYERS_OFFLOADED" && "$LAYERS_OFFLOADED" == "0/"* ]]; then
    ux_section "Priority: Fix GPU Layer Offload"
    ux_numbered 1 "Restart Ollama: ${UX_PRIMARY}docker compose restart ollama${UX_RESET}"
    ux_numbered 2 "Set env vars in docker-compose.yml and rebuild:"
    echo -e "   ${UX_MUTED}ollama:\n     environment:\n       OLLAMA_GPU_OVERHEAD: \"1073741824\"  # 1GB\n       OLLAMA_NUM_GPU: \"25\"${UX_RESET}"
    ux_numbered 3 "Check for CUDA compatibility issues: ${UX_PRIMARY}docker logs ollama 2>&1 | grep -i 'cuda'${UX_RESET}"
    ux_numbered 4 "Ensure Windows NVIDIA drivers are up to date."
else
    offloaded_count=$(echo "$LAYERS_OFFLOADED" | cut -d'/' -f1 2>/dev/null || echo 0)
    total_count=$(echo "$LAYERS_OFFLOADED" | cut -d'/' -f2 2>/dev/null || echo 0)
    
    if [ -n "$LAYERS_OFFLOADED" ] && [ "$offloaded_count" -ne "$total_count" ]; then
        ux_section "Optional: Optimize Partial Offload"
        ux_info "To offload more layers to the GPU, you can:"
        ux_bullet "Reduce OLLAMA_GPU_OVERHEAD in docker-compose.yml."
        ux_bullet "Close other programs using GPU memory (browsers, VS Code, etc)."
        ux_bullet "Restart the Ollama container."
    else
        ux_success "GPU setup appears to be working correctly."
        ux_section "Optional: Further Tuning"
        ux_bullet "Enable Flash Attention: ${UX_PRIMARY}OLLAMA_FLASH_ATTENTION: \"1\"${UX_RESET}"
        ux_bullet "Adjust parallel requests: ${UX_PRIMARY}OLLAMA_NUM_PARALLEL: \"2\"${UX_RESET}"
        ux_bullet "Adjust max loaded models: ${UX_PRIMARY}OLLAMA_MAX_LOADED_MODELS: \"2\"${UX_RESET}"
    fi
fi
echo ""

# =============================================================================
# WSL2 환경 참고사항
# =============================================================================
ux_header "WSL2 Environment Notes"
ux_section "nvidia-smi limitations"
ux_info "It's normal that 'nvidia-smi' does not work inside the container."
ux_bullet "The host's nvidia-smi is at ${UX_PRIMARY}/usr/lib/wsl/lib/nvidia-smi${UX_RESET}"
ux_bullet "This does not mean the GPU is unused; CUDA runtime works correctly."
ux_bullet "Ollama's logs are the best source of truth for GPU usage."
echo ""
ux_section "Recommended Commands"
ux_table_header "Command" "Description"
ux_table_row "make gpu-info" "Simple GPU hardware info"
ux_table_row "make gpu-status" "This detailed diagnostic script"
ux_table_row "make health" "Full stack health check"
echo ""
