#!/bin/sh
# shell-common/functions/ai_setup.sh
# One-command AI workspace orchestrator.
#
# Creates multiple git worktrees and sets up tmux sessions with
# 3-pane windows for each. Run from the main repo directory.
#
# Usage: ai-setup

ai_setup() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1:-}" in
        -h|--help|help)
            ux_header "ai-setup - AI workspace orchestrator"
            ux_info "Usage: ai-setup"
            ux_info ""
            ux_info "Interactive setup that creates git worktrees and"
            ux_info "tmux sessions with 3-pane windows in one step."
            ux_info ""
            ux_info "Steps:"
            ux_info "  1. Enter worktree agents  (e.g. claude codex)"
            ux_info "  2. Enter tmux windows     (e.g. claude codex gemini)"
            ux_info "  3. Worktrees + tmux sessions are created automatically"
            ux_info ""
            ux_info "Requirements: git, tmux, run from main repo (not worktree)"
            return 0
            ;;
    esac

    # --- Guards ---
    if ! command -v git >/dev/null 2>&1; then
        ux_error "git is not installed"; return 1
    fi
    if ! command -v tmux >/dev/null 2>&1; then
        ux_error "tmux is not installed"; return 1
    fi

    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || \
        { ux_error "Not inside a git repository"; return 1; }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" != "$git_common" ]; then
        ux_error "Cannot run from inside a worktree. Run from the main repo."
        return 1
    fi

    local project parent
    project="$(basename "$(git rev-parse --show-toplevel)")"
    parent="$(dirname "$(git rev-parse --show-toplevel)")"
    local repo_root
    repo_root="$(git rev-parse --show-toplevel)"

    ux_header "AI Workspace Setup"
    ux_info "Project: $project ($repo_root)"
    echo

    # --- Step 1: Read worktree agents ---
    local wt_input=""
    while [ -z "$wt_input" ]; do
        printf "%s❯%s Worktree agents (space-separated): " \
            "$(printf '\033[1;36m')" "$(printf '\033[0m')"
        read -r wt_input
        if [ -z "$wt_input" ]; then
            ux_error "At least one agent required."
        fi
    done

    # Validate worktree agents
    local wt_agents="" wt_count=0
    for a in $wt_input; do
        if ! _ts_known_agent "$a"; then
            ux_error "Unknown agent: $a"
            ux_info "Available: claude, codex, gemini, opencode, cursor, copilot"
            return 1
        fi
        wt_agents="$wt_agents $a"
        wt_count=$((wt_count + 1))
    done
    wt_agents="${wt_agents# }"

    # --- Step 2: Read tmux window agents ---
    local win_input=""
    while [ -z "$win_input" ]; do
        printf "%s❯%s Tmux windows per session (space-separated): " \
            "$(printf '\033[1;36m')" "$(printf '\033[0m')"
        read -r win_input
        if [ -z "$win_input" ]; then
            ux_error "At least one window required."
        fi
    done

    # Validate window agents
    local win_agents="" win_count=0
    for a in $win_input; do
        if ! _ts_known_agent "$a"; then
            ux_error "Unknown agent: $a"
            ux_info "Available: claude, codex, gemini, opencode, cursor, copilot"
            return 1
        fi
        win_agents="$win_agents $a"
        win_count=$((win_count + 1))
    done
    win_agents="${win_agents# }"

    echo

    # --- Step 3: Create worktrees ---
    ux_info "Creating worktrees..."
    local wt_paths="" wt_created=0
    for agent in $wt_agents; do
        # Check if worktree already exists for this agent
        local existing_path=""
        for dir in "$parent/${project}-${agent}"-*/; do
            if [ -d "$dir" ]; then
                existing_path="${dir%/}"
                break
            fi
        done

        if [ -n "$existing_path" ]; then
            ux_warning "  $(basename "$existing_path") already exists — skipping"
            wt_paths="$wt_paths $existing_path"
        else
            git_worktree_spawn "$agent" >/dev/null 2>&1
            # Discover the path just created
            local new_path=""
            for dir in "$parent/${project}-${agent}"-*/; do
                if [ -d "$dir" ]; then
                    new_path="${dir%/}"
                fi
            done
            if [ -n "$new_path" ]; then
                local new_branch
                new_branch="$(git -C "$new_path" rev-parse --abbrev-ref HEAD 2>/dev/null)"
                ux_success "  $(basename "$new_path") ($new_branch)"
                wt_paths="$wt_paths $new_path"
                wt_created=$((wt_created + 1))
            else
                ux_error "  Failed to create worktree for $agent"
            fi
        fi
    done
    wt_paths="${wt_paths# }"

    echo

    # --- Step 4: Create tmux sessions + windows ---
    ux_info "Creating tmux sessions..."
    local session_count=0 total_windows=0
    for wt_path in $wt_paths; do
        local session_name
        session_name="$(basename "$wt_path")"

        # Skip if session already exists
        if tmux has-session -t "=$session_name" 2>/dev/null; then
            ux_warning "  $session_name: session exists — skipping"
            continue
        fi

        local win_display=""
        for win_agent in $win_agents; do
            _tmux_add_agent_window "$session_name" "$win_agent" "$wt_path"
            if [ -z "$win_display" ]; then
                win_display="$win_agent"
            else
                win_display="$win_display | $win_agent"
            fi
            total_windows=$((total_windows + 1))
        done

        ux_success "  $session_name: $win_display"
        session_count=$((session_count + 1))
    done

    echo

    # --- Step 5: Summary ---
    ux_header "Setup complete"
    ux_info "  $wt_count worktrees, $session_count sessions, $total_windows windows total"

    # Show how to connect
    if [ -z "$TMUX" ]; then
        echo
        ux_info "Attach: tmux attach"
    else
        echo
        ux_info "Switch: Ctrl+b s (session list)"
    fi
}

alias ai-setup='ai_setup'
