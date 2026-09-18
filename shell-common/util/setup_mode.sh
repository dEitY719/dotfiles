#!/bin/sh
# shell-common/util/setup_mode.sh
# SSOT for setup-mode detection and proxy cleanup
# Sourced by both bash/main.bash and zsh/main.zsh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_setup_mode_read_lib="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/util/setup_mode_read.sh"
if [ -r "$_setup_mode_read_lib" ]; then
    # shellcheck disable=SC1091
    . "$_setup_mode_read_lib"
fi

_apply_setup_mode_config() {
    command -v _dotfiles_setup_mode >/dev/null 2>&1 || return 0
    local mode
    mode=$(_dotfiles_setup_mode)

    case "$mode" in
        external|public)
            # Public PC/Home or External PC/VPN (legacy 1/3 are canonicalised
            # by _dotfiles_setup_mode before we get here).
            # These modes should NOT have corporate proxy settings
            # Auto-clean proxy variables to prevent inherited settings
            # (common in WSL2 where Windows proxy is auto-inherited)
            unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY no_proxy all_proxy ALL_PROXY
            ;;
        internal)
            # Internal PC - proxy configured via proxy.local.sh
            # Do nothing here, let proxy.local.sh handle it
            ;;
    esac
}
