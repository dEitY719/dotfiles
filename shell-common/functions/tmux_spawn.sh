#!/bin/sh
# shell-common/functions/tmux_spawn.sh
# Create a tmux session with 3-pane layout.
#
# Usage: tmux-spawn [<agent>]
#
# Two modes:
#   1) Inside a worktree (e.g. dotfiles-claude-1)
#      -> session name: dotfiles-claude-1
#      -> agent auto-detected from directory name
#
#   2) Main repo (e.g. ~/dotfiles, branch: feat/login)
#      -> session name: dotfiles-feat/login
#      -> agent defaults to claude (or specify via argument)
#
# Layout:
#   +----------+----------+
#   |          | right-top|
#   |   LEFT   +----------+
#   | (ai-yolo)| right-bot|
#   +----------+----------+

_ts_known_agent() {
    case "$1" in
        claude|codex|gemini|opencode|cursor|copilot) return 0 ;;
        *) return 1 ;;
    esac
}

tmux_spawn() {
    if ! command -v tmux >/dev/null 2>&1; then
        ux_error "tmux is not installed"
        return 1
    fi

    case "${1:-}" in
        -h|--help|help)
            ux_header "tmux-spawn - create tmux session with 3-pane layout"
            ux_info "Usage: tmux-spawn [-w] [<agent>]"
            ux_info ""
            ux_info "Options:"
            ux_info "  -w           Add new window to current session (must be inside tmux)"
            ux_info ""
            ux_info "Modes:"
            ux_info "  (default)    Create new session with 3-pane layout"
            ux_info "  -w           Add 3-pane window to current session"
            ux_info ""
            ux_info "Session naming:"
            ux_info "  Worktree dir  session = dir name, agent auto-detected"
            ux_info "  Main repo     session = <project>-<branch>, agent = claude"
            ux_info ""
            ux_info "Agents: claude, codex, gemini, opencode, cursor, copilot"
            ux_info ""
            ux_info "Layout:"
            ux_info "  +----------+----------+"
            ux_info "  |          | right-top|"
            ux_info "  |   LEFT   +----------+"
            ux_info "  | (ai-yolo)| right-bot|"
            ux_info "  +----------+----------+"
            return 0
            ;;
    esac

    # Parse -w flag
    _ts_window_mode=0
    if [ "${1:-}" = "-w" ]; then
        _ts_window_mode=1
        shift
    fi

    _ts_arg="${1:-}"
    _ts_dir="$(pwd)"
    _ts_basename="$(basename "$_ts_dir")"
    _ts_agent=""
    _ts_session=""

    # --- Detect mode: worktree vs main repo ---
    # Worktree pattern: <project>-<agent>-<index>
    _ts_without_index="${_ts_basename%-*}"
    _ts_candidate="${_ts_without_index##*-}"

    if _ts_known_agent "$_ts_candidate"; then
        # Mode 1: worktree directory
        _ts_agent="$_ts_candidate"
        _ts_session="$_ts_basename"
    else
        # Mode 2: main repo — use <project>-<branch>
        _ts_project="$_ts_basename"
        _ts_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
        _ts_session="${_ts_project}-${_ts_branch}"
        _ts_agent="${_ts_arg:-claude}"
        unset _ts_project _ts_branch
    fi

    # Override agent if argument given
    if [ -n "$_ts_arg" ]; then
        if _ts_known_agent "$_ts_arg"; then
            _ts_agent="$_ts_arg"
        else
            ux_error "Unknown agent: $_ts_arg"
            ux_info  "Available: claude, codex, gemini, opencode, cursor, copilot"
            unset _ts_arg _ts_dir _ts_basename _ts_agent _ts_session \
                  _ts_without_index _ts_candidate
            return 1
        fi
    fi

    _ts_yolo="${_ts_agent}-yolo"

    # --- Window mode: add new window to current session ---
    if [ "$_ts_window_mode" = 1 ]; then
        if [ -z "$TMUX" ]; then
            ux_error "Option -w requires being inside a tmux session"
            unset _ts_arg _ts_dir _ts_basename _ts_agent _ts_session \
                  _ts_without_index _ts_candidate _ts_yolo _ts_window_mode
            return 1
        fi

        _ts_cur_session="$(tmux display-message -p '#{session_name}')"

        # Create new window named after agent
        tmux new-window -t "$_ts_cur_session" -n "$_ts_agent" -c "$_ts_dir"
        # Pane 1: right-top
        tmux split-window -h -t "$_ts_cur_session" -c "$_ts_dir"
        # Pane 2: right-bottom
        tmux split-window -v -t "$_ts_cur_session" -c "$_ts_dir"

        # Run ai-yolo in left pane (pane 0 of the new window)
        _ts_new_win="$(tmux display-message -p '#{window_index}')"
        tmux send-keys -t "${_ts_cur_session}:${_ts_new_win}.0" "$_ts_yolo" Enter

        # Focus left pane
        tmux select-pane -t "${_ts_cur_session}:${_ts_new_win}.0"

        ux_success "Window '$_ts_agent' added to session '$_ts_cur_session' (3 panes, running $_ts_yolo)"

        unset _ts_arg _ts_dir _ts_basename _ts_agent _ts_session \
              _ts_without_index _ts_candidate _ts_yolo _ts_window_mode \
              _ts_cur_session _ts_new_win
        return 0
    fi

    # Check if session already exists
    if tmux has-session -t "=$_ts_session" 2>/dev/null; then
        ux_warning "Session '$_ts_session' already exists"
        if [ -z "$TMUX" ]; then
            ux_info "Attaching..."
            tmux attach -t "$_ts_session"
        else
            ux_info "Switch: tmux switch-client -t '$_ts_session'"
        fi
        unset _ts_arg _ts_dir _ts_basename _ts_agent _ts_session \
              _ts_without_index _ts_candidate _ts_yolo _ts_window_mode
        return 0
    fi

    # --- Create session with 3-pane layout ---
    # Note: = prefix works for has-session but NOT for
    # session/pane-targeting commands in tmux 3.4
    # Pane 0: left  (will run ai-yolo)
    tmux new-session -d -s "$_ts_session" -n "$_ts_agent" -c "$_ts_dir"
    # Pane 1: right-top
    tmux split-window -h -t "$_ts_session" -c "$_ts_dir"
    # Pane 2: right-bottom (split right pane vertically)
    tmux split-window -v -t "$_ts_session" -c "$_ts_dir"

    # Run ai-yolo in the left pane (pane 0)
    tmux send-keys -t "${_ts_session}:0.0" "$_ts_yolo" Enter

    # Focus left pane
    tmux select-pane -t "${_ts_session}:0.0"

    ux_success "Session '$_ts_session' created (3 panes, running $_ts_yolo)"

    # Attach or advise
    if [ -z "$TMUX" ]; then
        tmux attach -t "$_ts_session"
    else
        ux_info "Switch: Ctrl+b s  or  tmux switch-client -t '$_ts_session'"
    fi

    unset _ts_arg _ts_dir _ts_basename _ts_agent _ts_session \
          _ts_without_index _ts_candidate _ts_yolo _ts_window_mode
}

tmux_teardown() {
    ux_require "tmux" || return 1

    local target="${1:-all}" sessions count s

    case "$target" in
        -h|--help|help)
            ux_header "tmux-teardown - kill tmux sessions"
            ux_info "Usage: tmux-teardown [all | <session-name>]"
            ux_info ""
            ux_info "  all (default)      kill ALL sessions"
            ux_info "  <session-name>     kill a specific session"
            return 0
            ;;
        all)
            sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"
            if [ -z "$sessions" ]; then
                ux_info "No tmux sessions running."
                return 0
            fi

            count="$(printf '%s\n' "$sessions" | wc -l)"
            ux_warning "Killing $count session(s):"
            printf '%s\n' "$sessions" | while IFS= read -r s; do
                ux_info "  $s"
            done

            tmux kill-server
            ux_success "All sessions killed."
            ;;
        *)
            if tmux has-session -t "=$target" 2>/dev/null; then
                tmux kill-session -t "$target"
                ux_success "Session '$target' killed."
            else
                ux_error "Session not found: $target"
                ux_info "Running sessions:"
                tmux list-sessions -F '  #{session_name}' 2>/dev/null || ux_info "  (none)"
                return 1
            fi
            ;;
    esac
}

alias tmux-spawn='tmux_spawn'
alias tmux-teardown='tmux_teardown'
