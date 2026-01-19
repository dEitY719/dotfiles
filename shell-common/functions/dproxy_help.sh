#!/bin/sh
# shell-common/functions/dproxy_help.sh
# dproxyHelp - shared between bash and zsh

dproxy_help() {
    ux_header "Docker Corporate Proxy Setup Guide"

    ux_section "1. Config File Location"
    ux_info "/etc/systemd/system/docker.service.d/http-proxy.conf"
    echo ""

    ux_section "2. Check Current Config"
    ux_bullet "Command: systemctl show --property=Environment docker"
    ux_info "Output: Environment=HTTP_PROXY=... HTTPS_PROXY=... NO_PROXY=..."
    echo ""

    ux_section "3. View Config File"
    ux_bullet "cat /etc/systemd/system/docker.service.d/http-proxy.conf"
    echo ""

    ux_section "4. Edit Config"
    ux_bullet "sudo nano /etc/systemd/system/docker.service.d/http-proxy.conf"
    ux_success "Then reload:"
    ux_bullet "sudo systemctl daemon-reload"
    ux_bullet "sudo systemctl restart docker"
    echo ""

    ux_section "5. Remove Config"
    ux_bullet "sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf"
    ux_success "Then reload:"
    ux_bullet "sudo systemctl daemon-reload"
    ux_bullet "sudo systemctl restart docker"
    echo ""

    ux_section "6. Test Connection"
    ux_bullet "docker pull alpine:latest"
    echo ""

    ux_section "7. Reset All (Danger)"
    ux_warning "Deletes all Docker drop-in configs:"
    ux_bullet "sudo rm -rf /etc/systemd/system/docker.service.d/"
    echo ""

    ux_divider
    echo ""
    ux_info "Quick Commands:"
    ux_bullet "${UX_SUCCESS}dproxy_setup${UX_RESET} : Interactive setup script"
    ux_bullet "${UX_SUCCESS}dproxy-help${UX_RESET}  : Show this help"
    ux_bullet "${UX_SUCCESS}dproxy_show${UX_RESET}  : Show current proxy config"
    echo ""
}

# Alias for dproxy-help format (using dash instead of underscore)
alias dproxy-help='dproxy_help'
