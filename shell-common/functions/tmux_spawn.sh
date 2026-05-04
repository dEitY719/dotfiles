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

# _tmux_add_agent_window <session> <agent> <dir> [account]
# Add a 3-pane window to a tmux session (creates session if needed).
# Layout: LEFT (agent-yolo) | RIGHT-TOP / RIGHT-BOTTOM
#
# Optional 4th arg `account` (issue #295): when set with agent=claude, the
# left pane runs `claude-yolo --user <account>` instead of plain
# `claude-yolo`. Other agents have no multi-account support so the value is
# ignored — the caller is responsible for rejecting that combination.
_tmux_add_agent_window() {
    local session="$1" agent="$2" dir="$3" account="${4-}"
    local yolo win
    if [ "$agent" = "claude" ] && [ -n "$account" ]; then
        yolo="${agent}-yolo --user ${account}"
    else
        yolo="${agent}-yolo"
    fi

    if tmux has-session -t "=$session" 2>/dev/null; then
        win=$(tmux new-window -P -F '#{window_index}' \
            -t "$session" -n "$agent" -c "$dir")
    else
        win=$(tmux new-session -d -P -F '#{window_index}' \
            -s "$session" -n "$agent" -c "$dir")
    fi

    # 3-pane layout
    tmux split-window -h -t "${session}:${win}" -c "$dir"
    tmux split-window -v -t "${session}:${win}" -c "$dir"

    # Run ai-yolo in pane 0, focus it
    tmux send-keys -t "${session}:${win}.0" "$yolo" Enter
    tmux select-pane -t "${session}:${win}.0"
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

    # --- Detect mode: worktree vs main repo (via git, not filename) ---
    # Filename-based detection fails once worktree names are free-form
    # (e.g. dotfiles-issue-11-1), so rely on git's own notion of worktree.
    _ts_git_common="$(git rev-parse --git-common-dir 2>/dev/null)"
    _ts_git_dir="$(git rev-parse --git-dir 2>/dev/null)"

    if [ -n "$_ts_git_common" ] && [ "$_ts_git_dir" != "$_ts_git_common" ]; then
        # Mode 1: inside a worktree — session = current dir basename
        _ts_session="$_ts_basename"
        _ts_agent="${_ts_arg:-claude}"
    else
        # Mode 2: main repo (or not in git) — session = <project>-<branch>
        _ts_project="$_ts_basename"
        _ts_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
        _ts_session="${_ts_project}-${_ts_branch}"
        _ts_agent="${_ts_arg:-claude}"
        unset _ts_project _ts_branch
    fi
    unset _ts_git_common _ts_git_dir

    # Validate agent if argument given
    if [ -n "$_ts_arg" ]; then
        if _ts_known_agent "$_ts_arg"; then
            _ts_agent="$_ts_arg"
        else
            ux_error "Unknown agent: $_ts_arg"
            ux_info  "Available: claude, codex, gemini, opencode, cursor, copilot"
            unset _ts_arg _ts_dir _ts_basename _ts_agent _ts_session
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
        _tmux_add_agent_window "$_ts_cur_session" "$_ts_agent" "$_ts_dir"

        ux_success "Window '$_ts_agent' added to session '$_ts_cur_session' (3 panes, running ${_ts_agent}-yolo)"

        unset _ts_arg _ts_dir _ts_basename _ts_agent _ts_session \
              _ts_without_index _ts_candidate _ts_yolo _ts_window_mode \
              _ts_cur_session
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
    _tmux_add_agent_window "$_ts_session" "$_ts_agent" "$_ts_dir"

    ux_success "Session '$_ts_session' created (3 panes, running ${_ts_agent}-yolo)"

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
