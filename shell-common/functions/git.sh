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
        # Show all commits
        eval "git --no-pager log $log_format $branch $args"
    else
        # Show only last 11 commits
        eval "git --no-pager log $log_format -n 11 $branch $args"
    fi
}

# Smart git log function (shows last 11 commits by default, all with -a/--all flag)
# Usage:
#   gl        - Show last 11 commits in graph format
#   gl -a     - Show all commits in graph format
#   gl --all  - Show all commits in graph format
gl() {
    _git_log_formatter "" "$@"
}

# Upstream git log function (shows commits from upstream/main by default)
# Usage:
#   glum       - Show last 11 commits from upstream/main
#   glum -a    - Show all commits from upstream/main
#   glum --all - Show all commits from upstream/main
glum() {
    _git_log_formatter "upstream/main" "$@"
}
