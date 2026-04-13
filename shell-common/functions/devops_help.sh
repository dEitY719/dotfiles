#!/bin/sh
# shell-common/functions/devops_help.sh
# Bundle: DevOps tool help functions

# --- docker_help (from docker_help.sh) ---

_docker_help_summary() {
    ux_info "Usage: docker-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "compose: dc | dcu | dcud | dcd | dcl | dce"
    ux_bullet_sub "compose-extra: dcps | dcb | dcr | dcdv | dcstop | dcstart"
    ux_bullet_sub "basics: dps | dpsa | di | dstats | dstop | drm | drmi | dlogs | dinspect"
    ux_bullet_sub "resources: ddf | dprune | dprune_full | dvols | dvol_rm | dnetwork_prune | dbuild_prune"
    ux_bullet_sub "utilities: dbash | denv | dinspect_env | dstopall | drmall | dexport | dinstall | dproxy_setup"
    ux_bullet_sub "details: docker-help <section>  (example: docker-help compose)"
}

_docker_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "compose"
    ux_bullet_sub "compose-extra"
    ux_bullet_sub "basics"
    ux_bullet_sub "resources"
    ux_bullet_sub "utilities"
}

_docker_help_rows_compose() {
    ux_table_row "dc" "docker compose" "Base command"
    ux_table_row "dcu" "docker compose up" "Foreground start"
    ux_table_row "dcud" "docker compose up -d" "Detached start"
    ux_table_row "dcd" "docker compose down" "Stop & remove"
    ux_table_row "dcl" "logs <svc>" "Smart logs (service/container)"
    ux_table_row "dce" "exec <svc> <cmd>" "Execute command"
}

_docker_help_rows_compose_extra() {
    ux_table_row "dcps" "docker compose ps" "Status"
    ux_table_row "dcb" "docker compose build" "Build services"
    ux_table_row "dcr" "docker compose restart" "Restart services"
    ux_table_row "dcdv" "down -v" "Stop & remove volumes"
    ux_table_row "dcstop" "stop" "Stop containers"
    ux_table_row "dcstart" "start" "Start containers"
}

_docker_help_rows_basics() {
    ux_table_row "dps" "docker ps" "Running containers"
    ux_table_row "dpsa" "docker ps -a" "All containers"
    ux_table_row "di/dim" "docker images" "List images"
    ux_table_row "dstats" "docker stats" "Resource usage"
    ux_table_row "dstop" "docker stop" "Stop container"
    ux_table_row "drm" "docker rm" "Remove container"
    ux_table_row "drmi" "docker rmi" "Remove image"
    ux_table_row "dlogs" "docker logs -f" "Follow logs"
    ux_table_row "dinspect" "docker inspect" "Inspect object"
}

_docker_help_rows_resources() {
    ux_table_row "ddf" "system df" "Disk usage"
    ux_table_row "dprune" "system prune -f" "Basic cleanup"
    ux_table_row "dprune_full" "full prune" "Deep cleanup (interactive)"
    ux_table_row "dvols" "volume ls -f dangling" "Dangling volumes"
    ux_table_row "dvol_rm" "volume rm" "Remove volume"
    ux_table_row "dnetwork_prune" "network prune" "Cleanup networks"
    ux_table_row "dbuild_prune" "builder prune" "Cleanup build cache"
}

_docker_help_rows_utilities() {
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

_docker_help_render_section() {
    ux_section "$1"
    "$2"
}

_docker_help_section_rows() {
    case "$1" in
        compose)
            _docker_help_rows_compose
            ;;
        compose-extra|extra)
            _docker_help_rows_compose_extra
            ;;
        basics|basic)
            _docker_help_rows_basics
            ;;
        resources|resource|prune)
            _docker_help_rows_resources
            ;;
        utilities|util|utils)
            _docker_help_rows_utilities
            ;;
        *)
            ux_error "Unknown docker-help section: $1"
            ux_info "Try: docker-help --list"
            return 1
            ;;
    esac
}

_docker_help_full() {
    ux_header "Docker / Docker Compose Quick Commands"

    _docker_help_render_section "Docker Compose Basics" _docker_help_rows_compose
    _docker_help_render_section "Docker Compose Extra" _docker_help_rows_compose_extra
    _docker_help_render_section "Docker Basics" _docker_help_rows_basics
    _docker_help_render_section "Resource Management" _docker_help_rows_resources
    _docker_help_render_section "Utilities" _docker_help_rows_utilities
}

docker_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _docker_help_summary
            ;;
        --list|list)
            _docker_help_list_sections
            ;;
        --all|all)
            _docker_help_full
            ;;
        *)
            _docker_help_section_rows "$1"
            ;;
    esac
}

alias docker-help='docker_help'

# --- proxy_help (from proxy_help.sh) ---

_proxy_help_summary() {
    ux_info "Usage: proxy-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "diagnostics: check-proxy | env | file | shell | conn | git"
    ux_bullet_sub "commands: \$http_proxy | \$https_proxy | \$no_proxy | env | grep proxy"
    ux_bullet_sub "set: export http_proxy | https_proxy | no_proxy"
    ux_bullet_sub "unset: unset HTTP_PROXY HTTPS_PROXY NO_PROXY"
    ux_bullet_sub "git: connectTimeout | lowSpeedLimit | lowSpeedTime | view config"
    ux_bullet_sub "related: check-network quick | check-network"
    ux_bullet_sub "notes: NO_PROXY commas | uppercase env | proxy-only check"
    ux_bullet_sub "details: proxy-help <section>  (example: proxy-help set)"
}

_proxy_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "diagnostics"
    ux_bullet_sub "commands"
    ux_bullet_sub "set"
    ux_bullet_sub "unset"
    ux_bullet_sub "git"
    ux_bullet_sub "related"
    ux_bullet_sub "notes"
}

_proxy_help_rows_diagnostics() {
    ux_bullet "check-proxy          Run full diagnostic"
    ux_bullet "check-proxy env      Environment variables only"
    ux_bullet "check-proxy file     proxy.local.sh file check"
    ux_bullet "check-proxy shell    Shell loading test"
    ux_bullet "check-proxy conn     Configured proxy connectivity test"
    ux_bullet "check-proxy git      Git configuration"
}

_proxy_help_rows_commands() {
    ux_bullet "echo \$http_proxy          Current proxy setting"
    ux_bullet "echo \$https_proxy         Current HTTPS proxy"
    ux_bullet "echo \$no_proxy            NO_PROXY exceptions"
    ux_bullet "env | grep -i proxy        Show all proxy vars"
}

_proxy_help_rows_set() {
    ux_bullet "export http_proxy=\"http://proxy.example.com:8080/\""
    ux_bullet "export https_proxy=\"http://proxy.example.com:8080/\""
    ux_bullet "export no_proxy=\"localhost,127.0.0.1,.internal.domain.com\""
}

_proxy_help_rows_unset() {
    ux_bullet "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"
}

_proxy_help_rows_git() {
    ux_bullet "git config --global http.connectTimeout 60    Increase timeout"
    ux_bullet "git config --global http.lowSpeedLimit 0      Disable low speed limit"
    ux_bullet "git config --global http.lowSpeedTime 999999   Disable low speed time"
    ux_bullet "git config --global -l | grep proxy           View git proxy config"
}

_proxy_help_rows_related() {
    ux_bullet "check-network quick       General internet access check"
    ux_bullet "check-network             DNS, HTTPS, git, apt, pip, curl checks"
}

_proxy_help_rows_notes() {
    ux_warning "NO_PROXY with spaces is not recognized - use commas only"
    ux_info "Some tools only recognize uppercase (HTTP_PROXY, HTTPS_PROXY)"
    ux_info "check-proxy focuses on proxy configuration only"
}

_proxy_help_render_section() {
    ux_section "$1"
    "$2"
}

_proxy_help_section_rows() {
    case "$1" in
        diagnostics|diag)
            _proxy_help_rows_diagnostics
            ;;
        commands|quick)
            _proxy_help_rows_commands
            ;;
        set|setting|setup)
            _proxy_help_rows_set
            ;;
        unset|disable|disabling)
            _proxy_help_rows_unset
            ;;
        git)
            _proxy_help_rows_git
            ;;
        related)
            _proxy_help_rows_related
            ;;
        notes|important)
            _proxy_help_rows_notes
            ;;
        *)
            ux_error "Unknown proxy-help section: $1"
            ux_info "Try: proxy-help --list"
            return 1
            ;;
    esac
}

_proxy_help_full() {
    ux_header "Proxy Configuration & Diagnostics"

    if type ux_section >/dev/null 2>&1; then
        _proxy_help_render_section "Diagnostic Commands" _proxy_help_rows_diagnostics
        _proxy_help_render_section "Quick Commands" _proxy_help_rows_commands
        _proxy_help_render_section "Setting Proxy (Corporate Environment)" _proxy_help_rows_set
        _proxy_help_render_section "Disabling Proxy" _proxy_help_rows_unset
        _proxy_help_render_section "Git Configuration" _proxy_help_rows_git
        _proxy_help_render_section "Related Diagnostics" _proxy_help_rows_related
        _proxy_help_render_section "Important Notes" _proxy_help_rows_notes
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

proxy_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _proxy_help_summary
            ;;
        --list|list)
            _proxy_help_list_sections
            ;;
        --all|all)
            _proxy_help_full
            ;;
        *)
            _proxy_help_section_rows "$1"
            ;;
    esac
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
