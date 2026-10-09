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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    command -v _dotfiles_setup_mode_proxy >/dev/null 2>&1 || return 0

    # public/external must not carry a corporate proxy: clean what WSL2 or the
    # parent environment inherited. internal is configured by proxy.local.sh,
    # and an unset/unknown mode is left alone.
    if [ "$(_dotfiles_setup_mode_proxy)" = "forbidden" ]; then
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY no_proxy all_proxy ALL_PROXY
    fi
}
