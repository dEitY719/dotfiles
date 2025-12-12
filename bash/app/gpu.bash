#!/bin/bash

# bash/app/gpu.bash
# GPU monitoring and diagnostics for WSL2 environment
# 사용 예: gpustatus, gpuinfo, gpu-mem, gpu-offload 등

# ═══════════════════════════════════════════════════════════════
# GPU Status & Monitoring Commands
# ═══════════════════════════════════════════════════════════════

# 전체 GPU 상태 진단 (5-part detailed diagnostic)
# 사용 예: gpustatus
# 또는 프로젝트 디렉토리에서: make gpu-status
alias gpustatus='(cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" && make gpu-status 2>/dev/null) || echo "LiteLLM Stack not found. Ensure GPU monitoring is set up."'

# GPU 간략 정보 (하드웨어 + 레이어 오프로드)
# 사용 예: gpuinfo
# 또는 프로젝트 디렉토리에서: make gpu-info
alias gpuinfo='(cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" && make gpu-info 2>/dev/null) || echo "LiteLLM Stack not found. Ensure GPU monitoring is set up."'

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
    ux_header "GPU Monitoring Commands"

    ux_section "LiteLLM Stack Project Commands"
    ux_table_row "gpustatus" "make gpu-status" "5-part detailed GPU diagnostic"
    ux_table_row "gpuinfo" "make gpu-info" "Brief GPU hardware + layer offload"
    echo ""

    ux_section "Ollama GPU Status"
    ux_table_row "gpu-offload" "docker logs ollama | grep offloaded" "Layer offload status (25/25 = good)"
    ux_table_row "gpu-mem" "docker logs ollama | grep gpu memory" "GPU memory recognition check"
    echo ""

    ux_section "WSL2 Host GPU Info"
    ux_table_row "gpu-info-basic" "nvidia-smi (WSL2 version)" "GPU hardware info, workload, temp"
    ux_table_row "gpu-memory" "nvidia-smi memory query" "Detailed memory info (CSV format)"
    ux_table_row "gpu-watch" "watch nvidia-smi" "Real-time GPU monitoring (Ctrl+C to exit)"
    echo ""

    ux_section "Common Use Cases"
    ux_bullet "Check GPU is working: ${UX_BOLD}gpustatus${UX_RESET}"
    ux_bullet "Quick GPU overview: ${UX_BOLD}gpuinfo${UX_RESET}"
    ux_bullet "Model layer offload: ${UX_BOLD}gpu-offload${UX_RESET} (should show 25/25)"
    ux_bullet "Memory usage real-time: ${UX_BOLD}gpu-watch${UX_RESET}"
    ux_bullet "Detailed memory breakdown: ${UX_BOLD}gpu-memory${UX_RESET}"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "GPU not using layers? → ${UX_BOLD}gpustatus${UX_RESET} for diagnosis"
    ux_bullet "Docker Ollama not found? → Ensure LiteLLM Stack is running (${UX_BOLD}docker ps${UX_RESET})"
    ux_bullet "nvidia-smi command not found? → WSL2 environment issue, use ${UX_BOLD}gpu-info-basic${UX_RESET}}"
    echo ""

    ux_section "Example Output Interpretation"
    echo ""
    ux_info "Good GPU layer offload:"
    echo "  offloaded 25/25 layers to GPU ← All layers on GPU"
    echo ""

    ux_info "Bad GPU layer offload:"
    echo "  offloaded 0/25 layers to GPU ← CPU mode (slow!)"
    echo ""

    ux_info "GPU memory info:"
    echo "  available=\"12.3 GiB\" free=\"13.8 GiB\" ← GPU recognized"
    echo ""
}

# Export function for use in other shells
export -f gpuhelp
