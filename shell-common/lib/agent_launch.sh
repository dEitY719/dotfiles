#!/bin/sh
# shellcheck shell=bash
# shell-common/lib/agent_launch.sh
# AI agent launch helpers shared by `gwt spawn` (functions/git_worktree_spawn.sh)
# and `tmux-spawn` (functions/tmux_spawn.sh), split out in #2156: the known
# agent list, the yolo command each launch path runs, the 3-pane tmux window
# (tmux-spawn / ai_setup only — gwt spawn dropped --tmux in #2355), and mise
# trust for a fresh worktree.
#
# Guard-free on purpose (no interactive guard, no output on source): it only
# defines functions, so non-interactive consumers (avatar_issue_watcher, the
# session:worktree-spawn skill) can source it.

_ts_known_agent() {
    case "$1" in
        claude|codex|agy|opencode|cursor|copilot) return 0 ;;
        *) return 1 ;;
    esac
}

# _tmux_add_agent_window <session> <agent> <dir>
# Add a 3-pane window to a tmux session (creates session if needed).
# Layout: LEFT (agent-yolo) | RIGHT-TOP / RIGHT-BOTTOM
# The account / --bg / prompt args went with `gwt spawn --tmux` (#2355).
_tmux_add_agent_window() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local session="$1" agent="$2" dir="$3"
    local yolo="${agent}-yolo" win

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

# ============================================================================
# _gwt_yolo_command — agent → yolo command dispatch (issue #243)
#
# Returns the literal command string to run for an agent's yolo mode.
# Bypasses shell alias expansion, which is unreliable inside function
# context — zsh in particular fails to expand `claude-yolo` from inside
# a function body, even via `eval`. Keeping the SSOT here means the
# alias files (claude.sh, codex.sh, agy.sh, opencode.sh) and the
# launch path stay in sync via grep, not via shell alias resolution.
#
# Output: command string on stdout, exit 0 on known agent.
# Failure: exit 1 on unknown / launch-unsupported agent.
# ============================================================================
_gwt_yolo_command() {
    # `--list` returns the supported agent names so call sites (e.g. the
    # "Supported with --launch" hint) derive from the same SSOT and cannot
    # drift from the case body below.
    #
    # Optional 2nd arg: account name (claude only — multi-account dispatcher,
    # issue #295). When set with --ai claude, the launch command becomes
    # `claude_yolo --user <account>`; other agents ignore it because they do
    # not support multi-account.
    case "$1" in
        --list)   echo "claude, codex, agy, opencode" ;;
        claude)
            if [ -n "${2-}" ]; then
                echo "claude_yolo --user $2"
            else
                echo "claude_yolo"
            fi
            ;;
        codex)    echo "codex --dangerously-bypass-approvals-and-sandbox" ;;
        agy)      echo "agy --dangerously-skip-permissions" ;;
        opencode) echo "opencode" ;;
        *)        return 1 ;;
    esac
}

# ============================================================================
# _agent_prompt_suffix <agent> <use_bg> <prompt> — the tail both launch paths
# append to the agent command (#650):
#   --bg                -> --bg ''
#   --bg --prompt X Y   -> --bg 'X Y'
#   --prompt X Y        -> 'X Y'
#   (none)              -> (empty)
# claude only: other agents have no --bg, and their first-message conventions
# are out of scope (#650). Single-quote-safe escape: ' -> '\''.
# ============================================================================
_agent_prompt_suffix() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local agent="$1" use_bg="${2-0}" prompt="${3-}" esc=""
    [ "$agent" = "claude" ] || return 0
    # Assigned apart from `local` so SC2155 cannot mask the sed exit status
    # (PR #652 gemini-code-assist review).
    if [ -n "$prompt" ]; then
        esc=$(printf '%s' "$prompt" | sed "s/'/'\\\\''/g")
    fi
    if [ "$use_bg" = 1 ]; then
        printf " --bg '%s'" "$esc"
    elif [ -n "$prompt" ]; then
        printf " '%s'" "$esc"
    fi
}

# ============================================================================
# _agent_launch_cmd <agent> [account] [use_bg] [prompt] — the full command
# `gwt spawn --launch` evals in the new worktree. Exit 1 on an agent with no
# yolo command (see _gwt_yolo_command).
# ============================================================================
_agent_launch_cmd() {
    local cmd
    cmd=$(_gwt_yolo_command "$1" "${2-}") || return 1
    printf '%s%s\n' "$cmd" "$(_agent_prompt_suffix "$1" "${3-0}" "${4-}")"
}

# _agent_mise_trust <dir> — mise keys trust per config-file path, so a fresh
# worktree directory is untrusted even though its mise.toml is identical to
# the main repo's (already-trusted) copy. Without this, the first `mise`
# invocation in the new worktree (e.g. via --launch) errors out.
_agent_mise_trust() {
    if [ -f "${1}/mise.toml" ] && command -v mise >/dev/null 2>&1; then
        mise trust "${1}/mise.toml" >/dev/null 2>&1
    fi
    return 0
}
