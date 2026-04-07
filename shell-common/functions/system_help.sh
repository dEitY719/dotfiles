#!/bin/sh
# shell-common/functions/system_help.sh
# Bundle: system utility help functions

# --- sys_help (from sys_help.sh) ---

sys_help() {
    ux_header "System Management Commands"

    ux_section "Process Management"
    ux_table_row "psgrep" "ps aux | grep <pattern>" "Find process by pattern"
    ux_table_row "psg" "ps aux | grep" "Find process"
    ux_table_row "kill9" "kill -9" "Force kill"
    ux_table_row "psa" "ps aux" "List all processes"

    ux_section "Network"
    ux_table_row "ports" "ss -tulanp" "Show open ports"
    ux_table_row "myip" "curl ipecho.net" "Public IP"
    ux_table_row "localip" "hostname -I" "Local IP"
    ux_table_row "ping" "ping -c 5" "Ping (5 times)"
    ux_table_row "check-network" "check-network" "Internet connectivity diagnostics"
    ux_table_row "ssh-help" "ssh-help" "SSH hosts and examples"

    ux_section "Monitoring"
    ux_table_row "top" "htop" "Process monitor"
    ux_table_row "meminfo" "free -m" "Memory usage"
    ux_table_row "cpuinfo" "lscpu" "CPU info"
    ux_table_row "diskusage" "df -h" "Disk usage"

    ux_section "Package Management (APT)"
    ux_table_row "update" "apt update" "Update lists"
    ux_table_row "upgrade" "apt upgrade" "Upgrade packages"
    ux_table_row "remove" "apt remove" "Remove package"
    ux_table_row "auto-remove" "apt autoremove" "Remove unused"

    ux_section "Log Viewing"
    ux_table_row "logs" "syslog" "System logs"
    ux_table_row "error" "error.log" "Error logs"
    ux_table_row "auth" "auth.log" "Auth logs"
}

alias sys-help='sys_help'

# --- gpu_help (from gpu_help.sh) ---

# Internal: Full help function (moved from tools/integrations/gpu.sh for co-location)
# Pure help-display function — no GPU tool dependencies, only ux_* calls
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

gpu_help() {
    # Show full help with --all or -a flag
    if [[ "$1" == "--all" ]] || [[ "$1" == "-a" ]]; then
        _gpu_help_full
        return 0
    fi

    ux_header "GPU Monitoring Commands"

    ux_section "Diagnostics & Monitoring"
    ux_table_row "gpustatus" "Full GPU diagnosis (5 sections)"
    ux_table_row "gpuinfo" "Quick GPU overview"
    ux_table_row "gpu-offload" "Layer offload status"
    ux_table_row "gpu-mem" "GPU memory check"
    ux_table_row "gpu-watch" "Real-time GPU monitor"


    ux_section "Quick Test"
    ux_bullet "Fast (1-2s): ${UX_BOLD}docker exec ollama ollama run tinyllama \"hi\"${UX_RESET}"
    ux_bullet "Full (10s+): ${UX_BOLD}docker exec ollama ollama run llama3:instruct \"hi\"${UX_RESET}"


    ux_section "Fix: GPU Layers at 0/25"
    ux_bullet "Edit docker-compose.yml (add to Ollama service):"
    ux_bullet "  OLLAMA_NUM_GPU: '25'"
    ux_bullet "  OLLAMA_FLASH_ATTENTION: '1'"
    ux_bullet "Restart: ${UX_BOLD}docker compose up -d ollama${UX_RESET}"


    ux_info "More details: ${UX_BOLD}gpu-help --all${UX_RESET}"
}

alias gpu-help='gpu_help'

# --- du_help (from du_help.sh) ---

du_help() {
    ux_header "Disk Usage Helper (du aliases)"

    ux_section "Commands"
    ux_table_row "dus" "du -sh ." "Current dir summary"
    ux_table_row "dud" "du -sh *" "Subdir summary (sorted)"
    ux_table_row "dsql" "du .sql" "SQL dump sizes"
    ux_table_row "dubig" "du top 10" "Top 10 largest items"

    ux_info "Tip: -h option means 'human-readable' (K, M, G)"
}

alias du-help='du_help'

# --- dir_help (from dir_help.sh) ---

dir_help() {
    ux_header "Directory Navigation"

    ux_section "Core Directories"
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "cd-dot" "\$DOTFILES_ROOT" "Dotfiles repository root"
    ux_table_row "cd-down" "\$HOME/downloads" "Downloads folder"
    ux_table_row "cd-work" "\$HOME/workspace" "Workspace root"

    ux_section "Windows (WSL)"
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "cd-wdocu" "Windows Documents" "Access Windows documents"
    ux_table_row "cd-wobsidian" "Windows Obsidian" "Obsidian vault location"
    ux_table_row "cd-wdown" "Windows Downloads" "Quick access to downloads"
    ux_table_row "cd-wpicture" "Windows Pictures" "Photo library"
    ux_table_row "cd-tilnote" "Obsidian TilNote" "TilNote vault"
    ux_table_row "cd-obsidian" "Obsidian vault" "Default vault in WSL"

    ux_section "PARA Method"
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "mkpara" "para/{archive,area,project,resource}" "Create PARA directories"
    ux_table_row "cd-para" "\$HOME/para" "PARA root"
    ux_table_row "cd-project" "\$HOME/para/project" "Projects workspace"
    ux_table_row "cd-area" "\$HOME/para/area" "Areas of responsibility"
    ux_table_row "cd-vault" "\$HOME/para/area/vault" "Vault under Areas"
    ux_table_row "cd-resource" "\$HOME/para/resource" "Reference materials"
    ux_table_row "cd-archive" "\$HOME/para/archive" "Archived items"

    ux_section "Windows Copy Utility"
    ux_table_header "Command" "Usage" "Purpose"
    ux_table_row "cp_wdown" "cp_wdown [options] <file...>" "Copy from Windows Downloads into WSL (run -h for details)"
}

alias dir-help='dir_help'

# --- network_help (from network_help.sh) ---

network_help() {
    ux_header "Network Connectivity Diagnostics"

    if type ux_section >/dev/null 2>&1; then
        ux_section "Diagnostic Commands"
        ux_bullet "check-network         Run full network diagnostic"
        ux_bullet "check-network quick   DNS + HTTPS + git quick check"
        ux_bullet "check-network dns     DNS resolution test"
        ux_bullet "check-network ping    ICMP ping test"
        ux_bullet "check-network https   HTTPS HEAD request test"
        ux_bullet "check-network git     Git remote access test"
        ux_bullet "check-network apt     APT repository reachability"
        ux_bullet "check-network pip     pip repository reachability"
        ux_bullet "check-network curl    curl GET request test"

        ux_section "Typical Use"
        ux_bullet "check-network         Verify internet access end-to-end"
        ux_bullet "check-network quick   Fast sanity check after shell startup"
        ux_bullet "check-proxy           Diagnose proxy-specific configuration"

        ux_section "What It Checks"
        ux_bullet "DNS lookup to confirm name resolution"
        ux_bullet "ICMP ping to detect low-level reachability"
        ux_bullet "HTTPS and curl requests to validate outbound web access"
        ux_bullet "git, apt, and pip endpoints for real tool-level access"

        ux_section "Important Notes"
        ux_info "ICMP ping may fail even when normal web traffic works"
        ux_info "APT check is skipped automatically on non-APT systems"
        ux_info "Use check-proxy for proxy variables and proxy.local.sh issues"
    else
        echo "Diagnostic Commands:"
        echo "  check-network       Run full network diagnostic"
        echo "  check-network dns   DNS resolution test"
        echo "  check-network ping  ICMP ping test"
        echo "  check-network https HTTPS HEAD request test"
    fi
}

network_check() {
    local check_network_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_network.sh"
    if [ -f "$check_network_script" ]; then
        bash "$check_network_script" "$@"
    else
        if type ux_error >/dev/null 2>&1; then
            ux_error "check_network.sh not found at $check_network_script"
        else
            echo "Error: check_network.sh not found at $check_network_script" >&2
        fi
        return 1
    fi
}

alias network-help='network_help'
alias check-network='network_check'
