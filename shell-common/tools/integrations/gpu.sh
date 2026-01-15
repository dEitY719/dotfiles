#!/bin/bash
# shell-common/tools/external/gpu.sh
# Auto-generated from bash/app/gpu.bash


# bash/app/gpu.bash
# GPU monitoring and diagnostics for WSL2 environment
# 범용 GPU 모니터링 도구 (프로젝트 독립적)
# 사용 예: gpustatus, gpuinfo, gpu-mem, gpu-offload 등

# ═══════════════════════════════════════════════════════════════
# GPU Diagnostic Script (범용)
# ═══════════════════════════════════════════════════════════════

# 전체 GPU 상태 진단 (5-part detailed diagnostic)
# WSL2 환경에 최적화된 범용 GPU 진단 스크립트
# 사용 예: gpustatus
gpustatus() {
    # dotfiles에서 gpu_status.sh 스크립트 경로
    local gpu_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/gpu_status.sh"

    if [ ! -f "$gpu_script" ]; then
        ux_error "GPU status script not found at: $gpu_script"
        return 1
    fi

    if [ ! -x "$gpu_script" ]; then
        ux_error "GPU status script is not executable"
        return 1
    fi

    # 스크립트 실행 (현재 디렉토리 유지)
    bash "$gpu_script"
}
alias gpu-status='gpustatus'

# GPU 간략 정보 (하드웨어 + 레이어 오프로드)
# 사용 예: gpuinfo
gpuinfo() {
    ux_header "GPU 하드웨어 정보"

    # 1. WSL2 호스트 GPU 정보
    ux_section "WSL2 호스트 GPU"
    if [ -x /usr/lib/wsl/lib/nvidia-smi ]; then
        /usr/lib/wsl/lib/nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null |
            awk -F, '{printf "  [GPU %s] %s (%s VRAM)\n", $1, $2, $3}'
    else
        ux_warning "nvidia-smi not found"
    fi
    echo ""

    # 2. Ollama GPU 메모리 인식
    ux_section "Ollama GPU 메모리"
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^ollama$"; then
        local gpu_mem
        gpu_mem=$(docker logs ollama 2>&1 | grep "gpu memory" | tail -1 | grep -oP 'available="\K[^"]+')
        if [ -n "$gpu_mem" ]; then
            ux_success "GPU 인식됨: $gpu_mem available"
        else
            ux_warning "GPU 메모리 로그 없음 (모델 미로드)"
        fi
    else
        ux_warning "Ollama 컨테이너 실행 중 아님"
    fi
    echo ""

    # 3. Ollama GPU 레이어 오프로드
    ux_section "GPU 레이어 오프로드"
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^ollama$"; then
        local offload
        offload=$(docker logs ollama 2>&1 | grep "offloaded.*layers to GPU" | tail -1 | grep -oP 'offloaded \K\d+/\d+' 2>/dev/null)
        if [ -n "$offload" ]; then
            if [[ "$offload" == "0/"* ]]; then
                ux_error "$offload (CPU 모드)"
            else
                ux_success "$offload layers"
            fi
        else
            ux_warning "아직 모델 로드 안됨"
        fi
    else
        ux_warning "Ollama 컨테이너 실행 중 아님"
    fi
    echo ""

    ux_info "상세 정보: ${UX_BOLD}gpustatus${UX_RESET}"
    echo ""
}
alias gpu-info='gpuinfo'

# ═══════════════════════════════════════════════════════════════
# Ollama GPU Monitoring
# ═══════════════════════════════════════════════════════════════

# Ollama 레이어 오프로드 상태 확인 (가장 중요!)
# 출력: "offloaded 25/25 layers to GPU" = 정상
# 출력: "offloaded 0/25 layers to GPU" = CPU 모드 (성능 저하)
alias gpu-offload='docker logs ollama 2>&1 | grep "offloaded.*layers to GPU" | tail -1'

# Ollama GPU 메모리 인식 확인
# 출력: "gpu memory" 로그 = GPU 정상 인식
# 정상 출력 예: "available=\"13.5 GiB\" free=\"13.9 GiB\""
alias gpu-mem='docker logs ollama 2>&1 | grep "gpu memory" | tail -1'

# ═══════════════════════════════════════════════════════════════
# WSL2 Host GPU Commands
# ═══════════════════════════════════════════════════════════════

# 기본 GPU 정보 확인 (nvidia-smi WSL2 버전)
# 워크로드, 온도, 메모리 등 종합 정보
alias gpu-info-basic='/usr/lib/wsl/lib/nvidia-smi'

# 상세 메모리 정보 (CSV 형식)
# 출력: name, memory.total, memory.free, memory.used
alias gpu-memory='/usr/lib/wsl/lib/nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used --format=csv'

# 실시간 GPU 모니터링 (1초 주기 갱신, Ctrl+C로 종료)
alias gpu-watch='watch -n 1 "/usr/lib/wsl/lib/nvidia-smi"'

# ═══════════════════════════════════════════════════════════════
# GPU Help Functions
# ═══════════════════════════════════════════════════════════════

# Internal: Full help function
_gpu_help_full() {
    ux_header "GPU Monitoring Commands (Complete)"

    ux_section "Core GPU Diagnostics"
    ux_table_row "gpustatus" "bash gpu_status.sh" "5-part detailed GPU diagnostic"
    ux_table_row "gpuinfo" "Compact GPU summary" "Brief GPU hardware + layer offload"
    echo ""

    ux_section "Ollama Docker GPU Status"
    ux_table_row "gpu-offload" "docker logs ollama | grep offloaded" "Layer offload status (25/25 = good)"
    ux_table_row "gpu-mem" "docker logs ollama | grep gpu memory" "GPU memory recognition check"
    echo ""

    ux_section "GPU Acceleration / Fixes"
    ux_table_row "docker compose restart ollama" "Restart Ollama" "Forces GPU layer re-init"
    ux_table_row "docker restart ollama" "Restart container" "Direct restart without compose"
    ux_table_row "dcr ollama" "Auto-detect restart" "Compose-aware restart"
    echo ""

    ux_section "WSL2 Host GPU Commands"
    ux_table_row "gpu-info-basic" "nvidia-smi" "GPU hardware info, workload, temp"
    ux_table_row "gpu-memory" "nvidia-smi memory (CSV)" "Detailed memory info"
    ux_table_row "gpu-watch" "Real-time GPU monitor" "Live monitoring (Ctrl+C to exit)"
    echo ""

    ux_section "Quick GPU Test"
    ux_bullet "Fast test (1-2s): ${UX_BOLD}docker exec ollama ollama run tinyllama \"hi\"${UX_RESET}"
    ux_bullet "Full test (10s+): ${UX_BOLD}docker exec ollama ollama run llama3:instruct \"hi\"${UX_RESET}"
    echo ""

    ux_section "Troubleshooting: GPU Layers at 0/25"
    ux_bullet "Add to docker-compose.yml (Ollama service):"
    echo "  environment:"
    echo "    OLLAMA_NUM_GPU: '25'           # or your GPU's layer count"
    echo "    OLLAMA_FLASH_ATTENTION: '1'    # enables flash attention"
    ux_bullet "Then restart: ${UX_BOLD}docker compose up -d ollama${UX_RESET}"
    echo ""

    ux_section "Output Examples"
    echo ""
    ux_info "✅ Good GPU layer offload:"
    echo "  offloaded 25/25 layers to GPU"
    echo ""
    ux_info "❌ Bad GPU layer offload:"
    echo "  offloaded 0/25 layers to GPU"
    echo ""

    ux_section "Usage Tips"
    ux_bullet "Full diagnosis: ${UX_BOLD}gpustatus${UX_RESET}"
    ux_bullet "Quick overview: ${UX_BOLD}gpuinfo${UX_RESET}"
    ux_bullet "Monitor layers: ${UX_BOLD}gpu-offload${UX_RESET}"
    ux_bullet "Check memory: ${UX_BOLD}gpu-memory${UX_RESET} or ${UX_BOLD}gpu-watch${UX_RESET}"
    echo ""
}

# Main help function (compact version)
# Note: gpu_help function is defined in shell-common/functions/gpu_help.sh
