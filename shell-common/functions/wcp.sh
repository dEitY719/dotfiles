#!/bin/sh
# shell-common/functions/wcp.sh
# cp that accepts Windows paths (WSL): "C:\Users\me\Videos" -> /mnt/c/Users/me/Videos.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

wcp() {
    local _n=$# _a
    while [ "$_n" -gt 0 ]; do
        _a=$1
        shift
        # Drive path (C:\..., C:/...) or UNC (\\wsl$\...). Flags/Linux paths pass through.
        case $_a in
        [A-Za-z]:[\\/]* | \\\\*)
            _a=$(wslpath -u "$_a") || {
                ux_error "wslpath failed: $_a"
                return 1
            }
            ;;
        esac
        set -- "$@" "$_a"
        _n=$((_n - 1))
    done
    command cp "$@"
}
