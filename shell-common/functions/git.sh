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
    # zsh compatibility: emulate POSIX sh to ensure word splitting on unquoted vars
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local current_branch protected_keywords branches branch
    local delete_list="" protected_list=""
    local delete_count=0 protected_count=0

    # Keywords that protect branches from deletion (contains matching)
    protected_keywords="backup keep wip"

    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
        ux_error "Not in a git repository or in detached HEAD state"
        return 1
    }

    branches=$(git for-each-ref --format='%(refname:short)' refs/heads)

    # Classify each branch: protected or delete candidate
    while IFS= read -r branch; do
        [ -n "$branch" ] || continue

        # Always protect main and current branch
        if [ "$branch" = "main" ] || [ "$branch" = "$current_branch" ]; then
            continue
        fi

        # Keyword-based protection: contains matching via case statement
        local is_protected=false
        for keyword in $protected_keywords; do
            case "$branch" in
                *"$keyword"*)
                    protected_list="${protected_list}  ${branch}
"
                    protected_count=$((protected_count + 1))
                    is_protected=true
                    break
                    ;;
            esac
        done
        [ "$is_protected" = true ] && continue

        delete_list="${delete_list}${branch}
"
        delete_count=$((delete_count + 1))
    done <<EOF
$branches
EOF

    # Count implicit protected branches (main + current)
    local total_protected=$protected_count
    total_protected=$((total_protected + 1))  # main
    if [ "$current_branch" != "main" ]; then
        total_protected=$((total_protected + 1))  # current branch
    fi

    # Show protected branches first (safety-first UX)
    ux_header "Protected branches:"
    ux_info "  main (always)"
    if [ "$current_branch" != "main" ]; then
        ux_info "  $current_branch (current)"
    fi
    while IFS= read -r branch; do
        [ -n "$branch" ] && ux_info "$branch (keyword)"
    done <<EOF
$protected_list
EOF

    if [ "$delete_count" -eq 0 ]; then
        ux_info "No local branches to delete"
        return 0
    fi

    # Show and execute deletions
    ux_header "Deleting $delete_count local branch(es):"
    while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        ux_info "  $branch"
        git branch -D "$branch" >/dev/null 2>&1
    done <<EOF
$delete_list
EOF

    ux_success "Done! Deleted $delete_count branch(es). Protected $total_protected branch(es)."
}

# ============================================================================
# Backward Compatibility Aliases
# ============================================================================
# Maintain short-form aliases for convenience while supporting standard naming
alias gl='git_log'
alias glum='git_log_upstream'
alias gprune='git_prune_remote'
alias git-clean-local='git_clean_local'
