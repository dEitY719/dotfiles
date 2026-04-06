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
    ux_require "git" || return 1
    ux_require "tmux" || return 1

    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || \
        { ux_error "Not inside a git repository"; return 1; }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" != "$git_common" ]; then
        ux_error "Cannot run from inside a worktree. Run from the main repo."
        return 1
    fi

    local project parent repo_root
    project="$(basename "$(git rev-parse --show-toplevel)")"
    parent="$(dirname "$(git rev-parse --show-toplevel)")"
    repo_root="$(git rev-parse --show-toplevel)"

    ux_header "AI Workspace Setup"
    ux_info "Project: $project ($repo_root)"
    echo

    # --- Step 1: Read worktree agents ---
    local wt_input="" a
    while [ -z "$wt_input" ]; do
        printf "%s❯%s Worktree agents (space-separated): " \
            "${UX_BOLD}${UX_INFO}" "${UX_RESET}"
        read -r wt_input || return 1
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
            "${UX_BOLD}${UX_INFO}" "${UX_RESET}"
        read -r win_input || return 1
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
    local wt_paths="" wt_created=0 agent existing_path new_path new_branch dir
    for agent in $wt_agents; do
        # Check if worktree already exists for this agent
        existing_path=""
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
            git_worktree_spawn "$agent" >/dev/null
            # Discover path from git worktree list (reliable across any index)
            new_path=""
            while IFS= read -r line; do
                case "$line" in
                    "worktree "*"-${agent}-"*)
                        new_path="${line#worktree }" ;;
                esac
            done <<EOF
$(git worktree list --porcelain)
EOF
            if [ -n "$new_path" ]; then
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
    local session_count=0 total_windows=0 wt_path session_name win_display win_agent
    for wt_path in $wt_paths; do
        session_name="$(basename "$wt_path")"

        # Skip if session already exists
        if tmux has-session -t "=$session_name" 2>/dev/null; then
            ux_warning "  $session_name: session exists — skipping"
            continue
        fi

        win_display=""
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

    # Restore terminal state (tmux session creation can disable onlcr)
    stty onlcr 2>/dev/null || true

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

ai_teardown() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force=false
    case "${1:-}" in
        -h|--help|help)
            ux_header "ai-teardown - tear down AI workspace"
            ux_info "Usage: ai-teardown [--force]"
            ux_info ""
            ux_info "Kills tmux sessions for this project's worktrees"
            ux_info "and removes all worktrees, leaving only main repo."
            ux_info ""
            ux_info "Options:"
            ux_info "  --force    discard uncommitted changes"
            return 0
            ;;
        --force) force=true ;;
    esac

    # --- Guards ---
    ux_require "git" || return 1

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

    # --- Discover worktrees ---
    local main_wt wt_paths="" wt_count=0 line wt
    main_wt="$(git rev-parse --show-toplevel)"

    while IFS= read -r line; do
        case "$line" in
            "worktree "*)
                wt="${line#worktree }"
                if [ "$wt" != "$main_wt" ]; then
                    wt_paths="$wt_paths $wt"
                    wt_count=$((wt_count + 1))
                fi
                ;;
        esac
    done <<EOF
$(git worktree list --porcelain)
EOF
    wt_paths="${wt_paths# }"

    if [ "$wt_count" -eq 0 ]; then
        ux_info "No worktrees to tear down."
        return 0
    fi

    ux_header "AI Workspace Teardown"
    ux_info "Project: $project"
    echo

    # --- Step 1: Kill tmux sessions for worktrees ---
    local sessions_killed=0 wt_path session_name
    ux_info "Killing tmux sessions..."
    for wt_path in $wt_paths; do
        session_name="$(basename "$wt_path")"
        if tmux has-session -t "=$session_name" 2>/dev/null; then
            tmux kill-session -t "$session_name"
            ux_success "  $session_name"
            sessions_killed=$((sessions_killed + 1))
        fi
    done
    if [ "$sessions_killed" -eq 0 ]; then
        ux_info "  (no matching sessions)"
    fi

    echo

    # --- Step 2: Remove worktrees ---
    ux_info "Removing worktrees..."
    local wt_removed=0 wt_name branch
    for wt_path in $wt_paths; do
        wt_name="$(basename "$wt_path")"

        # Check for uncommitted changes
        if [ "$force" != true ]; then
            if ! git -C "$wt_path" diff --quiet 2>/dev/null || \
               ! git -C "$wt_path" diff --cached --quiet 2>/dev/null; then
                ux_error "  $wt_name: uncommitted changes (use --force)"
                continue
            fi
        fi

        # Get branch before removing
        branch="$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)" || true

        # Remove worktree
        if git worktree remove "$wt_path" 2>/dev/null || \
           { [ "$force" = true ] && git worktree remove --force "$wt_path" 2>/dev/null; }; then
            wt_removed=$((wt_removed + 1))

            # Delete branch
            if [ -n "$branch" ] && [ "$branch" != "main" ] && \
               [ "$branch" != "master" ] && [ "$branch" != "HEAD" ]; then
                if git branch -d "$branch" 2>/dev/null; then
                    ux_success "  $wt_name ($branch deleted)"
                elif [ "$force" = true ] && git branch -D "$branch" 2>/dev/null; then
                    ux_success "  $wt_name ($branch force-deleted)"
                else
                    ux_success "  $wt_name (branch '$branch' kept — not merged)"
                fi
            else
                ux_success "  $wt_name"
            fi
        else
            ux_error "  $wt_name: failed to remove"
        fi
    done

    git worktree prune 2>/dev/null

    # Restore terminal state (tmux operations can disable onlcr)
    stty onlcr 2>/dev/null || true

    echo

    # --- Summary ---
    ux_header "Teardown complete"
    ux_info "  $sessions_killed sessions killed, $wt_removed worktrees removed"
}

alias ai-setup='ai_setup'
alias ai-teardown='ai_teardown'
