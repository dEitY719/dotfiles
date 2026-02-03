#!/bin/sh
# shell-common/functions/git.sh
# Portable git functions for bash and zsh
# (No bash-specific features)

# Override Oh My Zsh's git aliases with our functions (zsh only)
# In zsh, Oh My Zsh may define various git aliases, so we unalias them first
# to allow our function definitions to work properly
unalias gl gd glum glog 2>/dev/null || true

# ============================================================================
# Shared git log formatter (extracted common logic)
# ============================================================================
# Internal function: formats and displays git log with options
# Args:
#   $1 = branch reference (empty string for current branch, "upstream/main" for upstream)
#   $@ = additional arguments (parsed for -a/--all flag)
_git_log_formatter() {
    local branch="$1"
    shift
    local show_all=0
    local args=""

    # Parse arguments for -a/--all flag
    for arg in "$@"; do
        if [ "$arg" = "-a" ] || [ "$arg" = "--all" ]; then
            show_all=1
        else
            # Accumulate non-flag arguments
            if [ -z "$args" ]; then
                args="$arg"
            else
                args="$args $arg"
            fi
        fi
    done

    # Git log format string (shared between functions)
    local log_format="--graph --pretty=tformat:'%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an' --date=short"

    # Execute git log with appropriate flags
    if [ $show_all -eq 1 ]; then
        # Show all commits with pager enabled for page-by-page browsing
        eval "git log $log_format $branch $args"
    else
        # Show only last 11 commits (no pager needed for small output)
        eval "git --no-pager log $log_format -n 11 $branch $args"
    fi
}

# Smart git log function (shows last 11 commits by default, all with -a/--all flag)
# Usage:
#   git_log        - Show last 11 commits in graph format
#   git_log -a     - Show all commits in graph format
#   git_log --all  - Show all commits in graph format
git_log() {
    _git_log_formatter "" "$@"
}

# Upstream git log function (shows commits from upstream/main by default)
# Usage:
#   git_log_upstream       - Show last 11 commits from upstream/main
#   git_log_upstream -a    - Show all commits from upstream/main
#   git_log_upstream --all - Show all commits from upstream/main
git_log_upstream() {
    _git_log_formatter "upstream/main" "$@"
}

# ============================================================================
# Prune remote branches (except main)
# ============================================================================
# Delete all branches from a specific remote except the main branch
# Usage:
#   git_prune_remote origin   - Delete all origin/* branches except origin/main
#   git_prune_remote upstream - Delete all upstream/* branches except upstream/main
git_prune_remote() {
    if [ -z "$1" ]; then
        ux_error "Usage: gprune <remote-name>"
        ux_error "Example: gprune origin"
        return 1
    fi

    local remote="$1"
    local branch_count=0

    # Count branches to be deleted
    branch_count=$(git branch -r | grep "^[[:space:]]*$remote/" | grep -v "^[[:space:]]*$remote/main" | wc -l)

    if [ "$branch_count" -eq 0 ]; then
        ux_info "No branches to delete (keeping $remote/main)"
        return 0
    fi

    ux_header "Deleting $branch_count branch(es) from '$remote':"
    git branch -r | grep "^[[:space:]]*$remote/" | grep -v "^[[:space:]]*$remote/main" | sed 's/^[[:space:]]*//' | while read -r branch; do
        ux_info "Deleting: $branch"
        git branch -dr "$branch" >/dev/null 2>&1
    done

    ux_success "Done!"
}

# ============================================================================
# Git configuration setup
# ============================================================================
# Configure automatic upstream branch setup on push (recommended)
# Usage:
#   git_setup_auto_remote - Enable automatic remote branch creation on first push
git_setup_auto_remote() {
    git config --global push.autoSetupRemote true
    if [ $? -eq 0 ]; then
        ux_success "✓ push.autoSetupRemote enabled"
        ux_info "Now 'git push' will automatically create and track remote branches"
    else
        ux_error "Failed to set git config"
        return 1
    fi
}

# Auto-setup on shell load (runs only once, silently if already configured)
if ! git config --get push.autoSetupRemote >/dev/null 2>&1; then
    git config --global push.autoSetupRemote true 2>/dev/null || true
fi

# ============================================================================
# Backward Compatibility Aliases
# ============================================================================
# Maintain short-form aliases for convenience while supporting standard naming
alias gl='git_log'
alias glum='git_log_upstream'
alias gprune='git_prune_remote'
