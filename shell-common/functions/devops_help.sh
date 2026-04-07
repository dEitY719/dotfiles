#!/bin/sh
# shell-common/functions/devops_help.sh
# Bundle: DevOps tool help functions

# --- docker_help (from docker_help.sh) ---

docker_help() {
    ux_header "Docker / Docker Compose Quick Commands"

    ux_section "Docker Compose Basics"
    ux_table_row "dc" "docker compose" "Base command"
    ux_table_row "dcu" "docker compose up" "Foreground start"
    ux_table_row "dcud" "docker compose up -d" "Detached start"
    ux_table_row "dcd" "docker compose down" "Stop & remove"
    ux_table_row "dcl" "logs <svc>" "Smart logs (service/container)"
    ux_table_row "dce" "exec <svc> <cmd>" "Execute command"

    ux_section "Docker Compose Extra"
    ux_table_row "dcps" "docker compose ps" "Status"
    ux_table_row "dcb" "docker compose build" "Build services"
    ux_table_row "dcr" "docker compose restart" "Restart services"
    ux_table_row "dcdv" "down -v" "Stop & remove volumes"
    ux_table_row "dcstop" "stop" "Stop containers"
    ux_table_row "dcstart" "start" "Start containers"

    ux_section "Docker Basics"
    ux_table_row "dps" "docker ps" "Running containers"
    ux_table_row "dpsa" "docker ps -a" "All containers"
    ux_table_row "di/dim" "docker images" "List images"
    ux_table_row "dstats" "docker stats" "Resource usage"
    ux_table_row "dstop" "docker stop" "Stop container"
    ux_table_row "drm" "docker rm" "Remove container"
    ux_table_row "drmi" "docker rmi" "Remove image"
    ux_table_row "dlogs" "docker logs -f" "Follow logs"
    ux_table_row "dinspect" "docker inspect" "Inspect object"

    ux_section "Resource Management"
    ux_table_row "ddf" "system df" "Disk usage"
    ux_table_row "dprune" "system prune -f" "Basic cleanup"
    ux_table_row "dprune_full" "full prune" "Deep cleanup (interactive)"
    ux_table_row "dvols" "volume ls -f dangling" "Dangling volumes"
    ux_table_row "dvol_rm" "volume rm" "Remove volume"
    ux_table_row "dnetwork_prune" "network prune" "Cleanup networks"
    ux_table_row "dbuild_prune" "builder prune" "Cleanup build cache"

    ux_section "Utilities"
    ux_table_row "dbash" "dbash <name>" "Shell access (bash/sh)"
    ux_table_row "denv" "denv <name>" "Show env vars"
    ux_table_row "dinspect_env" "inspect env" "Inspect env section"
    ux_table_row "dstopall" "Stop all" "Stop all running"
    ux_table_row "drmall" "Remove all" "Remove all containers"
    ux_table_row "dexport" "Export all" "Backup to tar files"
    ux_table_row "dinstall" "Install script" "Install Docker on WSL"
    ux_table_row "dproxy_setup" "Proxy setup" "Corporate proxy config"

    ux_info "Note: 'docker compose' (V2) is used by default."
}

alias docker-help='docker_help'

# --- proxy_help (from proxy_help.sh) ---

proxy_help() {
    ux_header "Proxy Configuration & Diagnostics"

    if type ux_section >/dev/null 2>&1; then
        ux_section "Diagnostic Commands"
        ux_bullet "check-proxy          Run full diagnostic"
        ux_bullet "check-proxy env      Environment variables only"
        ux_bullet "check-proxy file     proxy.local.sh file check"
        ux_bullet "check-proxy shell    Shell loading test"
        ux_bullet "check-proxy conn     Configured proxy connectivity test"
        ux_bullet "check-proxy git      Git configuration"


        ux_section "Quick Commands"
        ux_bullet "echo \$http_proxy          Current proxy setting"
        ux_bullet "echo \$https_proxy         Current HTTPS proxy"
        ux_bullet "echo \$no_proxy            NO_PROXY exceptions"
        ux_bullet "env | grep -i proxy        Show all proxy vars"


        ux_section "Setting Proxy (Corporate Environment)"
        ux_bullet "export http_proxy=\"http://proxy.example.com:8080/\""
        ux_bullet "export https_proxy=\"http://proxy.example.com:8080/\""
        ux_bullet "export no_proxy=\"localhost,127.0.0.1,.internal.domain.com\""


        ux_section "Disabling Proxy"
        ux_bullet "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"


        ux_section "Git Configuration"
        ux_bullet "git config --global http.connectTimeout 60    Increase timeout"
        ux_bullet "git config --global http.lowSpeedLimit 0      Disable low speed limit"
        ux_bullet "git config --global http.lowSpeedTime 999999   Disable low speed time"
        ux_bullet "git config --global -l | grep proxy           View git proxy config"


        ux_section "Related Diagnostics"
        ux_bullet "check-network quick       General internet access check"
        ux_bullet "check-network             DNS, HTTPS, git, apt, pip, curl checks"


        ux_section "Important Notes"
        ux_warning "NO_PROXY with spaces is not recognized - use commas only"
        ux_info "Some tools only recognize uppercase (HTTP_PROXY, HTTPS_PROXY)"
        ux_info "check-proxy focuses on proxy configuration only"

    else
        # Fallback for minimal shells without UX library
        echo "Diagnostic Commands:"
        echo "  check-proxy          Run full diagnostic"
        echo "  check-proxy env      Environment variables only"
        echo "  check-proxy file     proxy.local.sh file check"
        echo "  check-network quick  General internet access check"
        echo ""
        echo "Quick Commands:"
        echo "  echo \$http_proxy         Current proxy setting"
        echo "  env | grep -i proxy      Show all proxy vars"

    fi
}

# Wrapper function for check_proxy.sh diagnostic
proxy_check() {
    local check_proxy_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_proxy.sh"
    if [ -f "$check_proxy_script" ]; then
        bash "$check_proxy_script" "$@"
    else
        # Error handling with fallback (guard ux_error)
        if type ux_error >/dev/null 2>&1; then
            ux_error "check_proxy.sh not found at $check_proxy_script"
        else
            echo "Error: check_proxy.sh not found at $check_proxy_script" >&2
        fi
        return 1
    fi
}

alias proxy-help='proxy_help'
alias check-proxy='proxy_check'

# --- dproxy_help (from dproxy_help.sh) ---

dproxy_help() {
    ux_header "Docker Corporate Proxy Setup Guide"

    ux_section "Commands"
    ux_table_row "dproxy_setup" "Interactive setup script" "Configure Docker proxy"
    ux_table_row "dproxy_show" "Show current proxy config" "Display active settings"
    ux_table_row "dproxy-help" "Show this help" ""

    ux_section "Config File"
    ux_info "/etc/systemd/system/docker.service.d/http-proxy.conf"

    ux_section "Quick Reference"
    ux_bullet "Check config: systemctl show --property=Environment docker"
    ux_bullet "Edit config: sudo nano /etc/systemd/system/docker.service.d/http-proxy.conf"
    ux_bullet "Apply changes: sudo systemctl daemon-reload && sudo systemctl restart docker"
    ux_bullet "Test connection: docker pull alpine:latest"
}

alias dproxy-help='dproxy_help'
