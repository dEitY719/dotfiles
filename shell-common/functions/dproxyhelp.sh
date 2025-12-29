#!/bin/sh
# shell-common/functions/dproxyhelp.sh
# dproxyHelp - shared between bash and zsh

dproxyhelp() {
    ux_header "Docker Corporate Proxy Setup Guide"

    ux_section "1. Config File Location"
    ux_info "/etc/systemd/system/docker.service.d/http-proxy.conf"
    echo ""

    ux_section "2. Check Current Config"
    ux_info "systemctl show --property=Environment docker"
    echo "  Output example:"
    echo "    Environment=HTTP_PROXY=http://... HTTPS_PROXY=http://... NO_PROXY=..."
    echo ""

    ux_section "3. View Config File"
    ux_info "cat /etc/systemd/system/docker.service.d/http-proxy.conf"
    echo ""

    ux_section "4. Edit Config"
    ux_info "sudo nano /etc/systemd/system/docker.service.d/http-proxy.conf"
    echo "  After edit:"
    echo "    ${UX_SUCCESS}sudo systemctl daemon-reload${UX_RESET}"
    echo "    ${UX_SUCCESS}sudo systemctl restart docker${UX_RESET}"
    echo ""

    ux_section "5. Remove Config"
    ux_info "sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf"
    echo "  After remove:"
    echo "    ${UX_SUCCESS}sudo systemctl daemon-reload${UX_RESET}"
    echo "    ${UX_SUCCESS}sudo systemctl restart docker${UX_RESET}"
    echo ""

    ux_section "6. Test Connection"
    ux_info "docker pull alpine:latest"
    echo ""

    ux_section "7. Reset All (Danger)"
    ux_warning "sudo rm -rf /etc/systemd/system/docker.service.d/"
    echo "  ⚠️  This deletes all drop-in configs!"
    echo ""

    ux_divider
    echo ""
    ux_info "Quick Commands:"
    ux_bullet "${UX_SUCCESS}dproxy_setup${UX_RESET} : Interactive setup script"
    ux_bullet "${UX_SUCCESS}dproxyhelp${UX_RESET}   : Show this help"
    ux_bullet "${UX_SUCCESS}dproxy_show${UX_RESET}  : Show current proxy config"
    echo ""
}
