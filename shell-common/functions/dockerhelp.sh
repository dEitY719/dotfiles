#!/bin/sh
# shell-common/functions/dockerhelp.sh
# dockerHelp - shared between bash and zsh

docker_help() {
    ux_header "Docker / Docker Compose Quick Commands"

    ux_section "Docker Compose Basics"
    ux_table_row "dc" "docker compose" "Base command"
    ux_table_row "dcu" "docker compose up" "Foreground start"
    ux_table_row "dcud" "docker compose up -d" "Detached start"
    ux_table_row "dcd" "docker compose down" "Stop & remove"
    ux_table_row "dcl" "logs <svc>" "Smart logs (service/container)"
    ux_table_row "dce" "exec <svc> <cmd>" "Execute command"
    echo ""

    ux_section "Docker Compose Extra"
    ux_table_row "dcps" "docker compose ps" "Status"
    ux_table_row "dcb" "docker compose build" "Build services"
    ux_table_row "dcr" "docker compose restart" "Restart services"
    ux_table_row "dcdv" "down -v" "Stop & remove volumes"
    ux_table_row "dcstop" "stop" "Stop containers"
    ux_table_row "dcstart" "start" "Start containers"
    echo ""

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
    echo ""

    ux_section "Resource Management"
    ux_table_row "ddf" "system df" "Disk usage"
    ux_table_row "dprune" "system prune -f" "Basic cleanup"
    ux_table_row "dprune_full" "full prune" "Deep cleanup (interactive)"
    ux_table_row "dvols" "volume ls -f dangling" "Dangling volumes"
    ux_table_row "dvol_rm" "volume rm" "Remove volume"
    ux_table_row "dnetwork_prune" "network prune" "Cleanup networks"
    ux_table_row "dbuild_prune" "builder prune" "Cleanup build cache"
    echo ""

    ux_section "Utilities"
    ux_table_row "dbash" "dbash <name>" "Shell access (bash/sh)"
    ux_table_row "denv" "denv <name>" "Show env vars"
    ux_table_row "dinspect_env" "inspect env" "Inspect env section"
    ux_table_row "dstopall" "Stop all" "Stop all running"
    ux_table_row "drmall" "Remove all" "Remove all containers"
    ux_table_row "dexport" "Export all" "Backup to tar files"
    ux_table_row "dinstall" "Install script" "Install Docker on WSL"
    ux_table_row "dproxy_setup" "Proxy setup" "Corporate proxy config"
    echo ""

    ux_info "Note: 'docker compose' (V2) is used by default."
    echo ""
}

# Alias for docker-help format (using dash instead of underscore)
alias docker-help='docker_help'
