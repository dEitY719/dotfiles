#!/bin/sh
# shell-common/util/setup_mode.sh
# SSOT for setup-mode detection and proxy cleanup
# Sourced by both bash/main.bash and zsh/main.zsh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_apply_setup_mode_config() {
    local setup_mode_file="$HOME/.dotfiles-setup-mode"

    if [ ! -f "$setup_mode_file" ]; then
        return 0
    fi

    local mode
    mode=$(cat "$setup_mode_file" 2>/dev/null)

    case "$mode" in
        1|3|external|public)
            # Public PC/Home (legacy 1) or External PC/VPN (legacy 3)
            # These modes should NOT have corporate proxy settings
            # Auto-clean proxy variables to prevent inherited settings
            # (common in WSL2 where Windows proxy is auto-inherited)
            unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY no_proxy
            ;;
        2|internal)
            # Internal PC (legacy 2) - proxy configured via proxy.local.sh
            # Do nothing here, let proxy.local.sh handle it
            ;;
    esac
}
