#!/bin/bash

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
    local gpu_script="/home/bwyoon/dotfiles/mytool/gpu_status.sh"

    if [ ! -f "$gpu_script" ]; then
        echo "❌ GPU status script not found at: $gpu_script"
        return 1
    fi

    if [ ! -x "$gpu_script" ]; then
        echo "❌ GPU status script is not executable"
        return 1
    fi

    # 스크립트 실행 (현재 디렉토리 유지)
    bash "$gpu_script"
}

# GPU 간략 정보 (하드웨어 + 레이어 오프로드)
# 사용 예: gpuinfo
gpuinfo() {
    echo ""
    printf "%s\n" "$(printf '═%.0s' {1..63})"
    printf "%-63s\n" "GPU 하드웨어 정보 (요약)"
    printf "%s\n" "$(printf '═%.0s' {1..63})"
    echo ""

    # 1. WSL2 호스트 GPU 정보
    if [ -x /usr/lib/wsl/lib/nvidia-smi ]; then
        echo "📌 WSL2 호스트 GPU:"
        /usr/lib/wsl/lib/nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null |
            awk -F, '{printf "  [GPU %s] %s (%s VRAM)\n", $1, $2, $3}'
    else
        echo "⚠️  nvidia-smi not found"
    fi
    echo ""

    # 2. Ollama GPU 메모리 인식
    echo "📌 Ollama GPU 메모리:"
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^ollama$"; then
        local gpu_mem
        gpu_mem=$(docker logs ollama 2>&1 | grep "gpu memory" | tail -1 | grep -oP 'available="\K[^"]+')
        if [ -n "$gpu_mem" ]; then
            echo "  ✅ GPU 인식됨: $gpu_mem available"
        else
            echo "  ⚠️  GPU 메모리 로그 없음 (모델 미로드)"
        fi
    else
        echo "  ⚠️  Ollama 컨테이너 실행 중 아님"
    fi
    echo ""

    # 3. Ollama GPU 레이어 오프로드
    echo "📌 GPU 레이어 오프로드:"
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^ollama$"; then
        local offload
        offload=$(docker logs ollama 2>&1 | grep "offloaded.*layers to GPU" | tail -1 | grep -oP 'offloaded \K\d+/\d+' 2>/dev/null)
        if [ -n "$offload" ]; then
            if [[ "$offload" == "0/"* ]]; then
                echo "  ❌ $offload (CPU 모드)"
            else
                echo "  ✅ $offload layers"
            fi
        else
            echo "  ⚠️  아직 모델 로드 안됨"
        fi
    else
        echo "  ⚠️  Ollama 컨테이너 실행 중 아님"
    fi
    echo ""

    echo "상세 정보: gpustatus"
    echo ""
}

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
# GPU Help Function
# ═══════════════════════════════════════════════════════════════

gpuhelp() {
    ux_header "GPU Monitoring Commands (Universal)"

    ux_section "Core GPU Diagnostics"
    ux_table_row "gpustatus" "bash gpu_status.sh" "5-part detailed GPU diagnostic"
    ux_table_row "gpuinfo" "Compact GPU summary" "Brief GPU hardware + layer offload"
    echo ""

    ux_section "Ollama Docker GPU Status"
    ux_table_row "gpu-offload" "docker logs ollama | grep offloaded" "Layer offload status (25/25 = good)"
    ux_table_row "gpu-mem" "docker logs ollama | grep gpu memory" "GPU memory recognition check"
    echo ""

    ux_section "WSL2 Host GPU Commands"
    ux_table_row "gpu-info-basic" "nvidia-smi (WSL2 /usr/lib/wsl/lib/)" "GPU hardware info, workload, temp"
    ux_table_row "gpu-memory" "nvidia-smi memory query (CSV)" "Detailed memory info (CSV format)"
    ux_table_row "gpu-watch" "watch -n 1 nvidia-smi" "Real-time GPU monitoring (Ctrl+C to exit)"
    echo ""

    ux_section "Common Use Cases"
    ux_bullet "Full GPU diagnosis: ${UX_BOLD}gpustatus${UX_RESET} (5 sections)"
    ux_bullet "Quick GPU overview: ${UX_BOLD}gpuinfo${UX_RESET} (3 key metrics)"
    ux_bullet "Model layer offload: ${UX_BOLD}gpu-offload${UX_RESET} (should show 25/25)"
    ux_bullet "Memory usage real-time: ${UX_BOLD}gpu-watch${UX_RESET}"
    ux_bullet "Detailed memory breakdown: ${UX_BOLD}gpu-memory${UX_RESET}"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "GPU not working? → ${UX_BOLD}gpustatus${UX_RESET} for full diagnosis"
    ux_bullet "Docker Ollama not running? → Check with ${UX_BOLD}docker ps${UX_RESET}"
    ux_bullet "nvidia-smi not found? → WSL2 uses /usr/lib/wsl/lib/nvidia-smi (not /usr/bin/)"
    ux_bullet "Ollama GPU layers at 0/25? → Run ${UX_BOLD}gpustatus${UX_RESET} for solutions"
    echo ""

    ux_section "Example Output Interpretation"
    echo ""
    ux_info "Good GPU layer offload:"
    echo "  offloaded 25/25 layers to GPU ← All layers on GPU ✅"
    echo ""

    ux_info "Bad GPU layer offload:"
    echo "  offloaded 0/25 layers to GPU ← CPU mode (very slow!) ❌"
    echo ""

    ux_info "GPU memory info:"
    echo "  available=\"12.3 GiB\" free=\"13.8 GiB\" ← GPU recognized ✅"
    echo ""

    ux_section "Project Integration"
    echo ""
    ux_info "If you have a project with 'make gpu-status' (like LiteLLM Stack):"
    echo "  Run: cd /path/to/project && make gpu-status"
    echo ""
    ux_info "For standalone GPU monitoring anywhere:"
    echo "  Run: gpustatus (uses dotfiles/mytool/gpu_status.sh)"
    echo ""
}

# Export function for use in other shells
export -f gpuhelp
