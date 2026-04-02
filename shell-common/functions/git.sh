#!/bin/sh
# shell-common/functions/git.sh
# Portable git functions for bash and zsh
# (No bash-specific features)

# Override Oh My Zsh's git aliases with our functions (zsh only)
unalias gl gd glum glog 2>/dev/null || true

# ============================================================================
# Shared git log formatter
# ============================================================================
_git_log_formatter() {
    local branch="$1"
    shift
    local show_all=0

    # Collect non-flag arguments via positional params
    local saved_args=""
    for arg in "$@"; do
        if [ "$arg" = "-a" ] || [ "$arg" = "--all" ]; then
            show_all=1
        else
            saved_args="$saved_args $arg"
        fi
    done

    local fmt='%Cred%h%Creset %s %C(dim white)(%ad %an)%Creset%C(blue)%d%Creset'

    if [ $show_all -eq 1 ]; then
        git log --graph --abbrev-commit --decorate=short --date=short \
            --pretty=format:"$fmt" $branch $saved_args
    else
        git --no-pager log --graph --abbrev-commit --decorate=short --date=short \
            --pretty=format:"$fmt" -n 11 $branch $saved_args
        echo
    fi
}

git_log() {
    _git_log_formatter "" "$@"
}

git_log_upstream() {
    _git_log_formatter "upstream/main" "$@"
}

# ============================================================================
# Prune remote branches (except main)
# ============================================================================
git_prune_remote() {
    if [ -z "$1" ]; then
        ux_error "Usage: gprune <remote-name>"
        ux_error "Example: gprune origin"
        return 1
    fi

    local remote="$1"

    # Capture branch list once, reuse for count and iteration
    local branches
    branches=$(git branch -r | grep "^[[:space:]]*$remote/" | grep -v "^[[:space:]]*$remote/main" | sed 's/^[[:space:]]*//')

    local branch_count
    branch_count=$(printf '%s\n' "$branches" | grep -c . 2>/dev/null || echo 0)

    if [ "$branch_count" -eq 0 ]; then
        ux_info "No branches to delete (keeping $remote/main)"
        return 0
    fi

    ux_header "Deleting $branch_count branch(es) from '$remote':"
    printf '%s\n' "$branches" | while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        ux_info "Deleting: $branch"
        git branch -dr "$branch" >/dev/null 2>&1
    done

    ux_success "Done!"
}

# ============================================================================
# Git configuration setup
# ============================================================================
git_setup_auto_remote() {
    if git config --get push.autoSetupRemote >/dev/null 2>&1; then
        return 0
    fi

    if git config --global push.autoSetupRemote true; then
        ux_success "push.autoSetupRemote enabled"
        ux_info "Now 'git push' will automatically create and track remote branches"
    else
        ux_error "Failed to set git config"
        return 1
    fi
}

# Auto-setup on shell load (silent)
git_setup_auto_remote >/dev/null 2>&1 || true

# ============================================================================
# Clean all local branches except main and current branch
# ============================================================================
git_clean_local() {
    # zsh compatibility: emulate POSIX sh to ensure word splitting on unquoted vars
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local current_branch protected_keywords branches branch
    local delete_list="" protected_list=""
    local delete_count=0 protected_count=0

    protected_keywords="backup keep wip"

    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
        ux_error "Not in a git repository or in detached HEAD state"
        return 1
    }

    branches=$(git for-each-ref --format='%(refname:short)' refs/heads)

    while IFS= read -r branch; do
        [ -n "$branch" ] || continue

        if [ "$branch" = "main" ] || [ "$branch" = "$current_branch" ]; then
            continue
        fi

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

    local total_protected=$protected_count
    total_protected=$((total_protected + 1))
    if [ "$current_branch" != "main" ]; then
        total_protected=$((total_protected + 1))
    fi

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

    ux_header "Deleting $delete_count local branch(es):"
    while IFS= read -r branch; do
        [ -n "$branch" ] && ux_info "  $branch"
    done <<EOF
$delete_list
EOF

    xargs -r git branch -D >/dev/null 2>&1 <<EOF
$delete_list
EOF

    ux_success "Done! Deleted $delete_count branch(es). Protected $total_protected branch(es)."
}

# ============================================================================
# Worktree add (git-crypt safe)
# Creates a worktree without checking out git-crypt encrypted files
# Usage: git_worktree_add <path> [<new-branch> [<start-point>]]
# ============================================================================
git_worktree_add() {
    if [ -z "$1" ]; then
        ux_error "Usage: git_worktree_add <path> [<new-branch> [<start-point>]]"
        return 1
    fi

    local wt_path="$1"
    local branch="$2"
    local start_point="$3"

    # Build worktree add command
    if [ -n "$branch" ] && [ -n "$start_point" ]; then
        git worktree add --no-checkout -b "$branch" "$wt_path" "$start_point"
    elif [ -n "$branch" ]; then
        git worktree add --no-checkout -b "$branch" "$wt_path"
    else
        git worktree add --no-checkout "$wt_path"
    fi || return 1

    # Sparse-checkout: include everything except git-crypt encrypted files
    git -C "$wt_path" sparse-checkout init --no-cone
    printf '/*\n!/.env\n!/.secrets\n' | git -C "$wt_path" sparse-checkout set --stdin

    git -C "$wt_path" checkout || {
        ux_error "Checkout failed in worktree: $wt_path"
        return 1
    }

    ux_success "Worktree ready: $wt_path"
    ux_info "  (git-crypt files excluded: .env, .secrets/)"
}

# ============================================================================
# Aliases
# ============================================================================
alias git-log='git_log'
alias gl='git-log'
alias git-log-upstream='git_log_upstream'
alias git-prune-remote='git_prune_remote'
alias git-clean-local='git_clean_local'
