#!/bin/sh
# shell-common/util/setup_mode.sh
# SSOT for setup-mode detection and proxy cleanup
# Sourced by both bash/main.bash and zsh/main.zsh

_apply_setup_mode_config() {
    local setup_mode_file="$HOME/.dotfiles-setup-mode"

    if [ ! -f "$setup_mode_file" ]; then
        return 0
    fi

    local mode
    mode=$(cat "$setup_mode_file" 2>/dev/null)

    case "$mode" in
        1|3)
            # Mode 1 (Public PC/Home) or Mode 3 (External PC/VPN)
            # These modes should NOT have corporate proxy settings
            # Auto-clean proxy variables to prevent inherited settings
            # (common in WSL2 where Windows proxy is auto-inherited)
            unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY no_proxy
            ;;
        2)
            # Mode 2 (Internal PC) - proxy configured via proxy.local.sh
            # Do nothing here, let proxy.local.sh handle it
            ;;
    esac
}
