#!/bin/sh
# shell-common/functions/network_help.sh
# Network connectivity diagnostic help (POSIX-compatible, shared between bash and zsh)

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
        ux_header "Diagnostic Commands:"
        ux_bullet "check-network       Run full network diagnostic"
        ux_bullet "check-network dns   DNS resolution test"
        ux_bullet "check-network ping  ICMP ping test"
        ux_bullet "check-network https HTTPS HEAD request test"
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
