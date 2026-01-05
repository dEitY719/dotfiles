#!/bin/sh
# shell-common/functions/git.sh
# Portable git functions for bash and zsh
# (No bash-specific features)

# Override Oh My Zsh's gl alias with our function (zsh only)
# In zsh, Oh My Zsh may have defined gl='git pull', so we unalias first
unalias gl 2>/dev/null || true

# Smart git log function (shows last 11 commits by default, all with -a/--all flag)
# Usage:
#   gl        - Show last 11 commits in graph format
#   gl -a     - Show all commits in graph format
#   gl --all  - Show all commits in graph format
gl() {
    local show_all=0
    local args=""

    # Parse arguments
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

    # Execute git log with appropriate flags
    # Use --no-pager to avoid paging for inline display
    if [ $show_all -eq 1 ]; then
        # Show all commits
        eval "git --no-pager log --graph --pretty=tformat:'%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an' --date=short $args"
    else
        # Show only last 11 commits
        eval "git --no-pager log --graph --pretty=tformat:'%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an' --date=short -n 11 $args"
    fi
}

# Upstream git log function (wrapper for gl() with upstream/main reference)
# Shows commits from upstream/main branch by default
# Usage:
#   glum       - Show last 11 commits from upstream/main
#   glum -a    - Show all commits from upstream/main
#   glum --all - Show all commits from upstream/main
glum() {
    local show_all=0
    local args=""

    # Parse arguments
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

    # Execute git log for upstream/main with appropriate flags
    # Use --no-pager to avoid paging for inline display
    if [ $show_all -eq 1 ]; then
        # Show all commits from upstream/main
        eval "git --no-pager log --graph --pretty=tformat:'%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an' --date=short upstream/main $args"
    else
        # Show only last 11 commits from upstream/main
        eval "git --no-pager log --graph --pretty=tformat:'%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an' --date=short -n 11 upstream/main $args"
    fi
}
