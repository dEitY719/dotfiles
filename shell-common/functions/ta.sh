#!/bin/sh
# shell-common/functions/ta.sh
# Quick attach to the first tmux session.
#
# Usage: ta
#
# - Outside tmux: attaches to the first session
# - Inside tmux: switches client to the first session
# - No sessions: prints info and exits

ta() {
    if ! command -v tmux >/dev/null 2>&1; then
        ux_error "tmux is not installed"
        return 1
    fi

    _ta_session="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | head -n 1)"

    if [ -z "$_ta_session" ]; then
        ux_info "No tmux sessions running."
        unset _ta_session
        return 1
    fi

    ux_info "Attaching to '$_ta_session'"

    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$_ta_session"
    else
        tmux attach -t "$_ta_session"
    fi

    unset _ta_session
}
