#!/bin/sh
# shell-common/functions/system_help.sh
# Bundle: system utility help functions

# --- sys_help (from sys_help.sh) ---

_sys_help_summary() {
    ux_info "Usage: sys-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "process: psgrep | psg | kill9 | psa"
    ux_bullet_sub "network: ports | myip | localip | ping | check-network | ssh-help"
    ux_bullet_sub "monitoring: top | meminfo | cpuinfo | diskusage"
    ux_bullet_sub "apt: update | upgrade | remove | auto-remove"
    ux_bullet_sub "logs: logs | error | auth"
    ux_bullet_sub "details: sys-help <section>  (example: sys-help network)"
}

_sys_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "process"
    ux_bullet_sub "network"
    ux_bullet_sub "monitoring"
    ux_bullet_sub "apt"
    ux_bullet_sub "logs"
}

_sys_help_rows_process() {
    ux_table_row "psgrep" "ps aux | grep <pattern>" "Find process by pattern"
    ux_table_row "psg" "ps aux | grep" "Find process"
    ux_table_row "kill9" "kill -9" "Force kill"
    ux_table_row "psa" "ps aux" "List all processes"
}

_sys_help_rows_network() {
    ux_table_row "ports" "ss -tulanp" "Show open ports"
    ux_table_row "myip" "curl ipecho.net" "Public IP"
    ux_table_row "localip" "hostname -I" "Local IP"
    ux_table_row "ping" "ping -c 5" "Ping (5 times)"
    ux_table_row "check-network" "check-network" "Internet connectivity diagnostics"
    ux_table_row "ssh-help" "ssh-help" "SSH hosts and examples"
}

_sys_help_rows_monitoring() {
    ux_table_row "top" "htop" "Process monitor"
    ux_table_row "meminfo" "free -m" "Memory usage"
    ux_table_row "cpuinfo" "lscpu" "CPU info"
    ux_table_row "diskusage" "df -h" "Disk usage"
}

_sys_help_rows_apt() {
    ux_table_row "update" "apt update" "Update lists"
    ux_table_row "upgrade" "apt upgrade" "Upgrade packages"
    ux_table_row "remove" "apt remove" "Remove package"
    ux_table_row "auto-remove" "apt autoremove" "Remove unused"
}

_sys_help_rows_logs() {
    ux_table_row "logs" "syslog" "System logs"
    ux_table_row "error" "error.log" "Error logs"
    ux_table_row "auth" "auth.log" "Auth logs"
}

_sys_help_render_section() {
    ux_section "$1"
    "$2"
}

_sys_help_section_rows() {
    case "$1" in
        process|proc)
            _sys_help_rows_process
            ;;
        network|net)
            _sys_help_rows_network
            ;;
        monitoring|monitor|mon)
            _sys_help_rows_monitoring
            ;;
        apt|package|packages)
            _sys_help_rows_apt
            ;;
        logs|log)
            _sys_help_rows_logs
            ;;
        *)
            ux_error "Unknown sys-help section: $1"
            ux_info "Try: sys-help --list"
            return 1
            ;;
    esac
}

_sys_help_full() {
    ux_header "System Management Commands"

    _sys_help_render_section "Process Management" _sys_help_rows_process
    _sys_help_render_section "Network" _sys_help_rows_network
    _sys_help_render_section "Monitoring" _sys_help_rows_monitoring
    _sys_help_render_section "Package Management (APT)" _sys_help_rows_apt
    _sys_help_render_section "Log Viewing" _sys_help_rows_logs
}

sys_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _sys_help_summary
            ;;
        --list|list|section|sections)
            _sys_help_list_sections
            ;;
        --all|all)
            _sys_help_full
            ;;
        *)
            _sys_help_section_rows "$1"
            ;;
    esac
}

alias sys-help='sys_help'

# --- gpu_help (from gpu_help.sh) ---

_gpu_help_summary() {
    ux_info "Usage: gpu-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "diagnostics: gpustatus | gpuinfo"
    ux_bullet_sub "docker: gpu-offload | gpu-mem"
    ux_bullet_sub "fixes: docker compose restart ollama | docker restart ollama | dcr ollama"
    ux_bullet_sub "wsl: gpu-info-basic | gpu-memory | gpu-watch"
    ux_bullet_sub "test: tinyllama | llama3:instruct"
    ux_bullet_sub "troubleshoot: OLLAMA_NUM_GPU | OLLAMA_FLASH_ATTENTION"
    ux_bullet_sub "examples: good vs bad layer offload"
    ux_bullet_sub "tips: gpustatus | gpuinfo | gpu-offload | gpu-memory | gpu-watch"
    ux_bullet_sub "details: gpu-help <section>  (example: gpu-help diagnostics)"
}

_gpu_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "diagnostics"
    ux_bullet_sub "docker"
    ux_bullet_sub "fixes"
    ux_bullet_sub "wsl"
    ux_bullet_sub "test"
    ux_bullet_sub "troubleshoot"
    ux_bullet_sub "examples"
    ux_bullet_sub "tips"
}

_gpu_help_rows_diagnostics() {
    ux_table_row "gpustatus" "bash gpu_status.sh" "5-part detailed GPU diagnostic"
    ux_table_row "gpuinfo" "Compact GPU summary" "Brief GPU hardware + layer offload"
}

_gpu_help_rows_docker() {
    ux_table_row "gpu-offload" "docker logs ollama | grep offloaded" "Layer offload status (25/25 = good)"
    ux_table_row "gpu-mem" "docker logs ollama | grep gpu memory" "GPU memory recognition check"
}

_gpu_help_rows_fixes() {
    ux_table_row "docker compose restart ollama" "Restart Ollama" "Forces GPU layer re-init"
    ux_table_row "docker restart ollama" "Restart container" "Direct restart without compose"
    ux_table_row "dcr ollama" "Auto-detect restart" "Compose-aware restart"
}

_gpu_help_rows_wsl() {
    ux_table_row "gpu-info-basic" "nvidia-smi" "GPU hardware info, workload, temp"
    ux_table_row "gpu-memory" "nvidia-smi memory (CSV)" "Detailed memory info"
    ux_table_row "gpu-watch" "Real-time GPU monitor" "Live monitoring (Ctrl+C to exit)"
}

_gpu_help_rows_test() {
    ux_bullet "Fast test (1-2s): ${UX_BOLD}docker exec ollama ollama run tinyllama \"hi\"${UX_RESET}"
    ux_bullet "Full test (10s+): ${UX_BOLD}docker exec ollama ollama run llama3:instruct \"hi\"${UX_RESET}"
}

_gpu_help_rows_troubleshoot() {
    ux_bullet "Add to docker-compose.yml (Ollama service):"
    echo "  environment:"
    echo "    OLLAMA_NUM_GPU: '25'           # or your GPU's layer count"
    echo "    OLLAMA_FLASH_ATTENTION: '1'    # enables flash attention"
    ux_bullet "Then restart: ${UX_BOLD}docker compose up -d ollama${UX_RESET}"
}

_gpu_help_rows_examples() {
    ux_info "✅ Good GPU layer offload:"
    echo "  offloaded 25/25 layers to GPU"
    echo ""
    ux_info "❌ Bad GPU layer offload:"
    echo "  offloaded 0/25 layers to GPU"
}

_gpu_help_rows_tips() {
    ux_bullet "Full diagnosis: ${UX_BOLD}gpustatus${UX_RESET}"
    ux_bullet "Quick overview: ${UX_BOLD}gpuinfo${UX_RESET}"
    ux_bullet "Monitor layers: ${UX_BOLD}gpu-offload${UX_RESET}"
    ux_bullet "Check memory: ${UX_BOLD}gpu-memory${UX_RESET} or ${UX_BOLD}gpu-watch${UX_RESET}"
}

_gpu_help_render_section() {
    ux_section "$1"
    "$2"
}

_gpu_help_section_rows() {
    case "$1" in
        diagnostics|diag)
            _gpu_help_rows_diagnostics
            ;;
        docker)
            _gpu_help_rows_docker
            ;;
        fixes|fix|acceleration)
            _gpu_help_rows_fixes
            ;;
        wsl|host)
            _gpu_help_rows_wsl
            ;;
        test)
            _gpu_help_rows_test
            ;;
        troubleshoot|troubleshooting)
            _gpu_help_rows_troubleshoot
            ;;
        examples|output)
            _gpu_help_rows_examples
            ;;
        tips|usage)
            _gpu_help_rows_tips
            ;;
        *)
            ux_error "Unknown gpu-help section: $1"
            ux_info "Try: gpu-help --list"
            return 1
            ;;
    esac
}

_gpu_help_full() {
    ux_header "GPU Monitoring Commands (Complete)"

    _gpu_help_render_section "Core GPU Diagnostics" _gpu_help_rows_diagnostics
    _gpu_help_render_section "Ollama Docker GPU Status" _gpu_help_rows_docker
    _gpu_help_render_section "GPU Acceleration / Fixes" _gpu_help_rows_fixes
    _gpu_help_render_section "WSL2 Host GPU Commands" _gpu_help_rows_wsl
    _gpu_help_render_section "Quick GPU Test" _gpu_help_rows_test
    _gpu_help_render_section "Troubleshooting: GPU Layers at 0/25" _gpu_help_rows_troubleshoot
    _gpu_help_render_section "Output Examples" _gpu_help_rows_examples
    _gpu_help_render_section "Usage Tips" _gpu_help_rows_tips
}

gpu_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _gpu_help_summary
            ;;
        --list|list|section|sections)
            _gpu_help_list_sections
            ;;
        --all|all|-a)
            _gpu_help_full
            ;;
        *)
            _gpu_help_section_rows "$1"
            ;;
    esac
}

alias gpu-help='gpu_help'

# --- du_help (from du_help.sh) ---

_du_help_summary() {
    ux_info "Usage: du-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "commands: dus | dud | dsql | dubig"
    ux_bullet_sub "tips: -h means human-readable (K, M, G)"
    ux_bullet_sub "details: du-help <section>  (example: du-help commands)"
}

_du_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "commands"
    ux_bullet_sub "tips"
}

_du_help_rows_commands() {
    ux_table_row "dus" "du -sh ." "Current dir summary"
    ux_table_row "dud" "du -sh *" "Subdir summary (sorted)"
    ux_table_row "dsql" "du .sql" "SQL dump sizes"
    ux_table_row "dubig" "du top 10" "Top 10 largest items"
}

_du_help_rows_tips() {
    ux_info "Tip: -h option means 'human-readable' (K, M, G)"
}

_du_help_render_section() {
    ux_section "$1"
    "$2"
}

_du_help_section_rows() {
    case "$1" in
        commands|cmd)
            _du_help_rows_commands
            ;;
        tips|tip)
            _du_help_rows_tips
            ;;
        *)
            ux_error "Unknown du-help section: $1"
            ux_info "Try: du-help --list"
            return 1
            ;;
    esac
}

_du_help_full() {
    ux_header "Disk Usage Helper (du aliases)"

    _du_help_render_section "Commands" _du_help_rows_commands
    _du_help_render_section "Tips" _du_help_rows_tips
}

du_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _du_help_summary
            ;;
        --list|list|section|sections)
            _du_help_list_sections
            ;;
        --all|all)
            _du_help_full
            ;;
        *)
            _du_help_section_rows "$1"
            ;;
    esac
}

alias du-help='du_help'

# --- dir_help (from dir_help.sh) ---

_dir_help_summary() {
    ux_info "Usage: dir-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "core: cd-dot | cd-down | cd-work"
    ux_bullet_sub "windows: cd-wdocu | cd-wobsidian | cd-wdown | cd-wpicture | cd-tilnote | cd-obsidian"
    ux_bullet_sub "para: mkpara | cd-para | cd-project | cd-area | cd-vault | cd-resource | cd-archive"
    ux_bullet_sub "copy: cp_wdown"
    ux_bullet_sub "details: dir-help <section>  (example: dir-help para)"
}

_dir_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "core"
    ux_bullet_sub "windows"
    ux_bullet_sub "para"
    ux_bullet_sub "copy"
}

_dir_help_rows_core() {
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "cd-dot" "\$DOTFILES_ROOT" "Dotfiles repository root"
    ux_table_row "cd-down" "\$HOME/downloads" "Downloads folder"
    ux_table_row "cd-work" "\$HOME/workspace" "Workspace root"
}

_dir_help_rows_windows() {
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "cd-wdocu" "Windows Documents" "Access Windows documents"
    ux_table_row "cd-wobsidian" "Windows Obsidian" "Obsidian vault location"
    ux_table_row "cd-wdown" "Windows Downloads" "Quick access to downloads"
    ux_table_row "cd-wpicture" "Windows Pictures" "Photo library"
    ux_table_row "cd-tilnote" "Obsidian TilNote" "TilNote vault"
    ux_table_row "cd-obsidian" "Obsidian vault" "Default vault in WSL"
}

_dir_help_rows_para() {
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "mkpara" "para/{archive,area,project,resource}" "Create PARA directories"
    ux_table_row "cd-para" "\$HOME/para" "PARA root"
    ux_table_row "cd-project" "\$HOME/para/project" "Projects workspace"
    ux_table_row "cd-area" "\$HOME/para/area" "Areas of responsibility"
    ux_table_row "cd-vault" "\$HOME/para/area/vault" "Vault under Areas"
    ux_table_row "cd-resource" "\$HOME/para/resource" "Reference materials"
    ux_table_row "cd-archive" "\$HOME/para/archive" "Archived items"
}

_dir_help_rows_copy() {
    ux_table_header "Command" "Usage" "Purpose"
    ux_table_row "cp_wdown" "cp_wdown [options] <file...>" "Copy from Windows Downloads into WSL (run -h for details)"
}

_dir_help_render_section() {
    ux_section "$1"
    "$2"
}

_dir_help_section_rows() {
    case "$1" in
        core)
            _dir_help_rows_core
            ;;
        windows|wsl)
            _dir_help_rows_windows
            ;;
        para)
            _dir_help_rows_para
            ;;
        copy|cp)
            _dir_help_rows_copy
            ;;
        *)
            ux_error "Unknown dir-help section: $1"
            ux_info "Try: dir-help --list"
            return 1
            ;;
    esac
}

_dir_help_full() {
    ux_header "Directory Navigation"

    _dir_help_render_section "Core Directories" _dir_help_rows_core
    _dir_help_render_section "Windows (WSL)" _dir_help_rows_windows
    _dir_help_render_section "PARA Method" _dir_help_rows_para
    _dir_help_render_section "Windows Copy Utility" _dir_help_rows_copy
}

dir_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _dir_help_summary
            ;;
        --list|list|section|sections)
            _dir_help_list_sections
            ;;
        --all|all)
            _dir_help_full
            ;;
        *)
            _dir_help_section_rows "$1"
            ;;
    esac
}

alias dir-help='dir_help'

# --- network_help (from network_help.sh) ---

_network_help_summary() {
    ux_info "Usage: network-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "diagnostics: check-network | quick | dns | ping | https | git | apt | pip | curl"
    ux_bullet_sub "typical: check-network | check-network quick | check-proxy"
    ux_bullet_sub "checks: DNS | ICMP | HTTPS | git | apt | pip"
    ux_bullet_sub "notes: ICMP fallback | APT auto-skip | check-proxy"
    ux_bullet_sub "details: network-help <section>  (example: network-help diagnostics)"
}

_network_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "diagnostics"
    ux_bullet_sub "typical"
    ux_bullet_sub "checks"
    ux_bullet_sub "notes"
}

_network_help_rows_diagnostics() {
    ux_bullet "check-network         Run full network diagnostic"
    ux_bullet "check-network quick   DNS + HTTPS + git quick check"
    ux_bullet "check-network dns     DNS resolution test"
    ux_bullet "check-network ping    ICMP ping test"
    ux_bullet "check-network https   HTTPS HEAD request test"
    ux_bullet "check-network git     Git remote access test"
    ux_bullet "check-network apt     APT repository reachability"
    ux_bullet "check-network pip     pip repository reachability"
    ux_bullet "check-network curl    curl GET request test"
}

_network_help_rows_typical() {
    ux_bullet "check-network         Verify internet access end-to-end"
    ux_bullet "check-network quick   Fast sanity check after shell startup"
    ux_bullet "check-proxy           Diagnose proxy-specific configuration"
}

_network_help_rows_checks() {
    ux_bullet "DNS lookup to confirm name resolution"
    ux_bullet "ICMP ping to detect low-level reachability"
    ux_bullet "HTTPS and curl requests to validate outbound web access"
    ux_bullet "git, apt, and pip endpoints for real tool-level access"
}

_network_help_rows_notes() {
    ux_info "ICMP ping may fail even when normal web traffic works"
    ux_info "APT check is skipped automatically on non-APT systems"
    ux_info "Use check-proxy for proxy variables and proxy.local.sh issues"
}

_network_help_render_section() {
    ux_section "$1"
    "$2"
}

_network_help_section_rows() {
    case "$1" in
        diagnostics|diag|commands)
            _network_help_rows_diagnostics
            ;;
        typical|use)
            _network_help_rows_typical
            ;;
        checks|what)
            _network_help_rows_checks
            ;;
        notes|important)
            _network_help_rows_notes
            ;;
        *)
            ux_error "Unknown network-help section: $1"
            ux_info "Try: network-help --list"
            return 1
            ;;
    esac
}

_network_help_full() {
    ux_header "Network Connectivity Diagnostics"

    if type ux_section >/dev/null 2>&1; then
        _network_help_render_section "Diagnostic Commands" _network_help_rows_diagnostics
        _network_help_render_section "Typical Use" _network_help_rows_typical
        _network_help_render_section "What It Checks" _network_help_rows_checks
        _network_help_render_section "Important Notes" _network_help_rows_notes
    else
        echo "Diagnostic Commands:"
        echo "  check-network       Run full network diagnostic"
        echo "  check-network dns   DNS resolution test"
        echo "  check-network ping  ICMP ping test"
        echo "  check-network https HTTPS HEAD request test"
    fi
}

network_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _network_help_summary
            ;;
        --list|list|section|sections)
            _network_help_list_sections
            ;;
        --all|all)
            _network_help_full
            ;;
        *)
            _network_help_section_rows "$1"
            ;;
    esac
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
