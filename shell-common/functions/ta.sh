#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/ta.sh
# Quick attach to the first tmux session.
#
# Usage: ta
#
# - Outside tmux: attaches to the first session
# - Inside tmux: switches client to the first session
# - No sessions: prints info and exits

ta() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    case "${1:-}" in
        -h|--help|help)
            ux_usage "ta" "" "Attach (or switch) to the first tmux session"
            return 0
            ;;
    esac

    ux_require "tmux" || return 1

    local _ta_session
    _ta_session="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | head -n 1)"

    if [ -z "$_ta_session" ]; then
        ux_info "No tmux sessions running."
        return 1
    fi

    ux_info "Attaching to '$_ta_session'"

    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$_ta_session"
    else
        tmux attach -t "$_ta_session"
    fi
}

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func ta "tmux attach helper"
