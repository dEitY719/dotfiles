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

    # Check if session already exists
    if tmux has-session -t "=$_ts_session" 2>/dev/null; then
        ux_warning "Session '$_ts_session' already exists"
        if [ -z "$TMUX" ]; then
            ux_info "Attaching..."
            tmux attach -t "=$_ts_session"
        else
            ux_info "Switch: tmux switch-client -t '=$_ts_session'"
        fi
        unset _ts_arg _ts_dir _ts_basename _ts_agent _ts_session \
              _ts_without_index _ts_candidate _ts_yolo
        return 0
    fi

    # --- Create session with 3-pane layout ---
    # Pane 0: left  (will run ai-yolo)
    tmux new-session -d -s "$_ts_session" -c "$_ts_dir"
    # Pane 1: right-top
    tmux split-window -h -t "=$_ts_session" -c "$_ts_dir"
    # Pane 2: right-bottom (split right pane vertically)
    tmux split-window -v -t "=$_ts_session" -c "$_ts_dir"

    # Run ai-yolo in the left pane (pane 0)
    tmux send-keys -t "=${_ts_session}:0.0" "$_ts_yolo" Enter

    # Focus left pane
    tmux select-pane -t "=${_ts_session}:0.0"

    ux_success "Session '$_ts_session' created (3 panes, running $_ts_yolo)"

    # Attach or advise
    if [ -z "$TMUX" ]; then
        tmux attach -t "=$_ts_session"
    else
        ux_info "Switch: Ctrl+b s  or  tmux switch-client -t '=$_ts_session'"
    fi

    unset _ts_arg _ts_dir _ts_basename _ts_agent _ts_session \
          _ts_without_index _ts_candidate _ts_yolo
}

alias tmux-spawn='tmux_spawn'
