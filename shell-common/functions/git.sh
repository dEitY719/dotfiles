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
    # Keep it compact + copy-friendly while still showing date/author.
    # (Avoid custom colors; rely on git's default coloring for decorations, if any.)
    local log_format="--graph --abbrev-commit --decorate=short --date=short --pretty=format:'%Cred%h%Creset %s %C(dim white)(%ad %an)%Creset%C(blue)%d%Creset'"

    # Execute git log with appropriate flags
    if [ $show_all -eq 1 ]; then
        # Show all commits with pager enabled for page-by-page browsing
        eval "git log $log_format $branch $args"
    else
        # Show only last 11 commits (no pager needed for small output)
        eval "git --no-pager log $log_format -n 11 $branch $args"
        # Ensure newline after output so prompt appears on new line
        echo
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
#   (Auto-runs on shell load; only applies config once, silently if already set)
git_setup_auto_remote() {
    # Already configured: return silently (idempotent)
    if git config --get push.autoSetupRemote >/dev/null 2>&1; then
        return 0
    fi

    # First-time setup with feedback
    git config --global push.autoSetupRemote true
    if [ $? -eq 0 ]; then
        ux_success "✓ push.autoSetupRemote enabled"
        ux_info "Now 'git push' will automatically create and track remote branches"
    else
        ux_error "Failed to set git config"
        return 1
    fi
}

# Auto-setup on shell load (silent: redirects all output)
git_setup_auto_remote >/dev/null 2>&1 || true

# ============================================================================
# Clean all local branches except main and current branch
# ============================================================================
# Force-delete every local branch except main and the one currently checked out.
# No branch switching required — safe to run from any branch.
# Usage:
#   git_clean_local - Delete all local branches except main and current
git_clean_local() {
    local current_branch exclude_pattern branch_count=0

    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
        ux_error "Not in a git repository or in detached HEAD state"
        return 1
    }

    # Build exclusion pattern: always protect main + current branch
    if [ "$current_branch" = "main" ]; then
        exclude_pattern='^main$'
    else
        exclude_pattern="^(main|${current_branch})$"
    fi

    branch_count=$(git for-each-ref --format='%(refname:short)' refs/heads | grep -cvE "$exclude_pattern")

    if [ "$branch_count" -eq 0 ]; then
        ux_info "No local branches to delete"
        return 0
    fi

    if [ "$current_branch" = "main" ]; then
        ux_header "Deleting $branch_count local branch(es) except main:"
    else
        ux_header "Deleting $branch_count local branch(es) (keeping: main, $current_branch):"
    fi

    git for-each-ref --format='%(refname:short)' refs/heads | grep -vE "$exclude_pattern" | while read -r branch; do
        ux_info "  $branch"
    done

    # Force delete all branches matching the exclusion pattern
    git for-each-ref --format='%(refname:short)' refs/heads | grep -vE "$exclude_pattern" | xargs -r git branch -D

    ux_success "Done! All local branches deleted (kept: main${current_branch:+ and $current_branch})."
}

# ============================================================================
# Backward Compatibility Aliases
# ============================================================================
# Maintain short-form aliases for convenience while supporting standard naming
alias gl='git_log'
alias glum='git_log_upstream'
alias gprune='git_prune_remote'
alias git-clean-local='git_clean_local'
