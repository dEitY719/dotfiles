#!/bin/sh
# shell-common/functions/gpuhelp.sh
# gpuHelp - shared between bash and zsh

gpuhelp() {
    # Show full help with --all or -a flag
    if [[ "$1" == "--all" ]] || [[ "$1" == "-a" ]]; then
        _gpuhelp_full
        return 0
    fi

    ux_header "GPU Monitoring Commands"

    ux_section "Diagnostics & Monitoring"
    ux_table_row "gpustatus" "Full GPU diagnosis (5 sections)"
    ux_table_row "gpuinfo" "Quick GPU overview"
    ux_table_row "gpu-offload" "Layer offload status"
    ux_table_row "gpu-mem" "GPU memory check"
    ux_table_row "gpu-watch" "Real-time GPU monitor"
    echo ""

    ux_section "Quick Test"
    ux_bullet "Fast (1-2s): ${UX_BOLD}docker exec ollama ollama run tinyllama \"hi\"${UX_RESET}"
    ux_bullet "Full (10s+): ${UX_BOLD}docker exec ollama ollama run llama3:instruct \"hi\"${UX_RESET}"
    echo ""

    ux_section "Fix: GPU Layers at 0/25"
    ux_bullet "Edit docker-compose.yml (add to Ollama service):"
    echo "    OLLAMA_NUM_GPU: '25'"
    echo "    OLLAMA_FLASH_ATTENTION: '1'"
    ux_bullet "Restart: ${UX_BOLD}docker compose up -d ollama${UX_RESET}"
    echo ""

    ux_info "More details: ${UX_BOLD}gpuhelp --all${UX_RESET}"
}
