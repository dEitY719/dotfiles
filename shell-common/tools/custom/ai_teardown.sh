#!/bin/bash
# shell-common/tools/custom/ai_teardown.sh
# ai-teardown — kill this project's worktree tmux sessions and remove the worktrees.
#
# PATH executable since #2195 (~/.local/bin/ai-teardown via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'ai-teardown'` resolve it too.
# functions/ai_setup.sh keeps the `ai_teardown` / `ai-teardown` names as a thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

main() {
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
        "")
            # No arguments — proceed normally
            ;;
        *)
            ux_warning "Unexpected arguments: $*"
            ux_info "Usage: ai-teardown [--force]"
            ux_info "Run 'ai-teardown --help' for details."
            return 1
            ;;
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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
