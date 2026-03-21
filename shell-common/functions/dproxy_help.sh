#!/bin/sh
# shell-common/functions/dproxy_help.sh

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
