#!/bin/sh
# shell-common/functions/git.sh
# Portable git functions for bash and zsh
# (No bash-specific features)

# Override Oh My Zsh's git aliases with our functions (zsh only)
unalias gl gd glum glog gwt 2>/dev/null || true

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
# ============================================================================
# gwt — git worktree dispatcher
# Usage: gwt <subcommand> [args...]
# ============================================================================
gwt() {
    case "${1:-}" in
        add)      shift; git_worktree_add "$@" ;;
        list|ls)  shift; git_worktree_list "$@" ;;
        remove|rm) shift; git_worktree_remove "$@" ;;
        prune)    shift; git worktree prune "$@" ;;
        spawn)    shift; git_worktree_spawn "$@" ;;
        teardown) shift; git_worktree_teardown "$@" ;;
        -h|--help|help|"")
            ux_header "gwt - git worktree manager"
            ux_info "Usage: gwt <command> [args...]"
            ux_info ""
            ux_info "Commands:"
            ux_info "  add <path> [branch] [start]    create git-crypt safe worktree"
            ux_info "  list, ls                       list worktrees (with hints)"
            ux_info "  remove, rm <path|all> [--force] remove worktree + branch"
            ux_info "  prune                          clean up stale worktree refs"
            ux_info "  spawn [ai] [--task slug]       create AI worktree (run from main repo)"
            ux_info "  teardown [--force]             self-cleanup (run from inside worktree)"
            ux_info ""
            ux_info "Run 'gwt <command> --help' for command-specific help."
            return 0
            ;;
        *)
            ux_error "Unknown command: $1. Run 'gwt help' for usage."
            return 1
            ;;
    esac
}

# ============================================================================
# Worktree list — formatted output with column headers and remove hint
# Usage: git_worktree_list
# ============================================================================
git_worktree_list() {
    local wt_output
    wt_output="$(git worktree list)"

    local wt_count
    wt_count=$(printf '%s\n' "$wt_output" | wc -l)

    ux_header "Git worktrees ($wt_count)"
    {
        printf '[path] [commit] [branch]\n'
        printf '%s\n' "$wt_output"
    } | column -t

    if [ "$wt_count" -gt 1 ]; then
        echo
        ux_info "To remove: gwt remove [path]"
    fi
}

# ============================================================================
# Worktree remove — remove worktree AND its associated branch
# Usage: git_worktree_remove <path> [--force]
# ============================================================================
git_worktree_remove() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1:-}" in
        -h|--help|help)
            ux_header "gwt remove - remove worktree and branch"
            ux_info "Usage: gwt remove <path|agent|all> [--force]"
            ux_info ""
            ux_info "  <path>     full or relative worktree path"
            ux_info "  <agent>    agent name (claude, codex, gemini, ...)"
            ux_info "             removes ALL worktrees matching *-<agent>-*"
            ux_info "  all        remove ALL non-main worktrees"
            ux_info "  --force    force remove + force delete unmerged branch"
            return 0
            ;;
        "")
            ux_error "Usage: gwt remove <path|agent> [--force]"
            return 1
            ;;
    esac

    local target="$1"
    local force=false
    [ "${2:-}" = "--force" ] && force=true

    # "all" — remove every non-main worktree
    if [ "$target" = "all" ]; then
        local main_wt
        main_wt="$(git worktree list --porcelain | head -1)"
        main_wt="${main_wt#worktree }"

        local all_wts="" all_count=0
        while IFS= read -r line; do
            case "$line" in
                "worktree "*)
                    local wt="${line#worktree }"
                    if [ "$wt" != "$main_wt" ]; then
                        all_wts="${all_wts}${wt}
"
                        all_count=$((all_count + 1))
                    fi
                    ;;
            esac
        done <<EOF
$(git worktree list --porcelain)
EOF

        if [ "$all_count" -eq 0 ]; then
            ux_info "No extra worktrees to remove."
            return 0
        fi

        ux_warning "This will remove $all_count worktree(s):"
        while IFS= read -r wt; do
            [ -n "$wt" ] || continue
            ux_info "  $wt"
        done <<EOF
$all_wts
EOF

        if [ "$force" != true ]; then
            printf 'Proceed? [y/N] '
            read -r answer
            case "$answer" in
                [yY]*) ;;
                *) ux_info "Aborted."; return 0 ;;
            esac
        fi

        local fail_count=0
        while IFS= read -r wt; do
            [ -n "$wt" ] || continue
            _gwt_remove_one "$wt" "$force" || fail_count=$((fail_count + 1))
        done <<EOF
$all_wts
EOF
        [ "$fail_count" -eq 0 ] && return 0 || return 1
    fi

    # Known agent names — always resolve as agent pattern, never as local path
    case "$target" in
        claude|codex|gemini|opencode|cursor|copilot|agent)
            ;;  # fall through to agent resolve below
        *)
            # Not an agent name: treat as direct path
            if [ -d "$target" ] || [ -e "$target" ]; then
                _gwt_remove_one "$target" "$force"
                return $?
            fi
            ;;
    esac

    # Resolve agent name (or unknown target) to worktree path(s)
    local project parent matches=""
    project="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")"
    parent="$(dirname "$(git rev-parse --show-toplevel 2>/dev/null)")"
    local match_count=0

    for dir in "$parent/${project}-${target}"-*/; do
        if [ -d "$dir" ]; then
            matches="${matches}${dir%/}
"
            match_count=$((match_count + 1))
        fi
    done

    if [ "$match_count" -eq 0 ]; then
        # Fallback: check for registered but missing worktrees (orphan cleanup)
        local wt_registered=""
        wt_registered="$(git worktree list --porcelain | while IFS= read -r line; do
            case "$line" in
                "worktree "*"-${target}-"*) printf '%s\n' "${line#worktree }" ;;
            esac
        done)"

        if [ -n "$wt_registered" ]; then
            git worktree prune
            ux_success "Pruned stale worktree refs for '$target'"
            git for-each-ref --format='%(refname:short)' "refs/heads/wt/${target}/" | while IFS= read -r branch; do
                if git branch -d "$branch" 2>/dev/null; then
                    ux_success "Branch deleted: $branch"
                elif [ "$force" = true ]; then
                    git branch -D "$branch" 2>/dev/null
                    ux_success "Branch force-deleted: $branch"
                else
                    ux_warning "Branch '$branch' not fully merged. Use --force to delete."
                fi
            done
            return 0
        fi

        ux_error "No worktree found: $target"
        ux_info "  No *-${target}-* worktrees exist."
        ux_info "  Run 'gwt list' to see available worktrees."
        return 1
    fi

    # Remove each matched worktree
    while IFS= read -r wt_path; do
        [ -n "$wt_path" ] || continue
        _gwt_remove_one "$wt_path" "$force"
    done <<EOF
$matches
EOF
}

# Internal: remove a single worktree + its branch
_gwt_remove_one() {
    local wt_path="$1" force="$2"

    # Detect branch before removing worktree
    local branch=""
    if [ -d "$wt_path" ]; then
        branch="$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)" || true
    fi

    # Remove worktree
    if ! git worktree remove "$wt_path" 2>/dev/null; then
        if [ "$force" = true ]; then
            git worktree remove --force "$wt_path" || { ux_error "Failed to remove: $wt_path"; return 1; }
        else
            ux_error "Cannot remove: $wt_path"
            ux_info "  Use: gwt remove $wt_path --force"
            return 1
        fi
    fi
    git worktree prune

    ux_success "Worktree removed: $wt_path"

    # Delete branch (skip main/master)
    if [ -n "$branch" ] && [ "$branch" != "main" ] && [ "$branch" != "master" ] && [ "$branch" != "HEAD" ]; then
        if git branch -d "$branch" 2>/dev/null; then
            ux_success "Branch deleted: $branch"
        elif [ "$force" = true ]; then
            git branch -D "$branch" 2>/dev/null
            ux_success "Branch force-deleted: $branch"
        else
            ux_warning "Branch '$branch' not fully merged. Use --force to delete."
        fi
    fi
}

git_worktree_add() {
    case "${1:-}" in
        -h|--help|help)
            ux_header "gwt add - git-crypt safe worktree"
            ux_info "Usage: gwt add <path> [<new-branch> [<start-point>]]"
            ux_info "  Creates a worktree with git-crypt encrypted files excluded"
            return 0
            ;;
        "")
            ux_error "Usage: gwt add <path> [<new-branch> [<start-point>]]"
            return 1
            ;;
    esac

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
    # Dynamically parse .gitattributes for filter=git-crypt patterns
    local repo_root excludes="" exclude_display=""
    repo_root="$(git rev-parse --show-toplevel)"
    if [ -f "$repo_root/.gitattributes" ]; then
        while IFS= read -r line; do
            case "$line" in
                *filter=git-crypt*)
                    local pattern
                    pattern="$(printf '%s' "$line" | awk '{print $1}')"
                    excludes="${excludes}!/${pattern}\n"
                    exclude_display="${exclude_display} ${pattern}"
                    ;;
            esac
        done < "$repo_root/.gitattributes"
    fi

    git -C "$wt_path" sparse-checkout init --no-cone
    printf "/*\n${excludes}" | git -C "$wt_path" sparse-checkout set --stdin

    git -C "$wt_path" checkout || {
        ux_error "Checkout failed in worktree: $wt_path"
        return 1
    }

    ux_success "Worktree ready: $wt_path"
    if [ -n "$exclude_display" ]; then
        ux_info "  git-crypt excluded:${exclude_display}"
    fi
}

# ============================================================================
# Worktree spawn — auto-index, auto-branch, log
# Usage: git_worktree_spawn [<agent>] [--task <slug>] [--base <ref>] [--tmux]
# ============================================================================
git_worktree_spawn() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local task="" base="" agent="" use_tmux=0

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help|help)
                ux_header "gwt spawn - AI worktree auto-creation"
                ux_info "Usage: gwt spawn [<agent>] [--task <slug>] [--base <ref>] [--tmux]"
                ux_info ""
                ux_info "Arguments:"
                ux_info "  <agent>          claude | codex | gemini | opencode | cursor (auto-detect if omitted)"
                ux_info "  --task <slug>    Add task slug to branch name"
                ux_info "  --base <ref>     Base branch/commit (default: origin/main)"
                ux_info "  --tmux           Auto-create tmux session/window with 3-pane layout"
                ux_info ""
                ux_info "Examples:"
                ux_info "  gwt spawn                          # auto-detect AI (default=claude)"
                ux_info "  gwt spawn claude                   # ../<project>-claude-1  wt/claude/1"
                ux_info "  gwt spawn codex --task login-fix   # ../<project>-codex-1   wt/codex/1-login-fix"
                ux_info "  gwt spawn gemini --tmux            # worktree + tmux window"
                return 0
                ;;
            --task) task="$2"; shift 2 ;;
            --base) base="$2"; shift 2 ;;
            --tmux) use_tmux=1; shift ;;
            claude|codex|gemini|opencode|cursor|copilot)
                agent="$1"; shift ;;
            *) ux_error "Unknown option: $1. Use --help for usage."; return 1 ;;
        esac
    done

    # Validate --tmux dependency
    if [ "$use_tmux" = 1 ] && ! command -v tmux >/dev/null 2>&1; then
        ux_error "tmux is not installed (required for --tmux)"
        return 1
    fi

    # Must be inside a git repo, NOT a worktree
    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        ux_error "Not inside a git repository"; return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" != "$git_common" ]; then
        ux_error "Cannot spawn from inside a worktree. Run from the main repo."
        return 1
    fi

    # Detect agent (explicit arg > env vars > fallback)
    if [ -z "$agent" ]; then
        if [ "${CLAUDECODE:-}" = "1" ]; then agent="claude"
        elif [ "${GEMINI_CLI:-}" = "1" ]; then agent="gemini"
        elif [ "${CODEX_CLI:-}" = "1" ]; then agent="codex"
        elif [ "${OPENCODE:-}" = "1" ]; then agent="opencode"
        elif [ "${CURSOR:-}" = "1" ] || [ "${TERM_PROGRAM:-}" = "cursor" ]; then agent="cursor"
        else agent="claude"
        fi
    fi

    # Compute project, parent, next index
    local project parent next_index=1
    project="$(basename "$(git rev-parse --show-toplevel)")"
    parent="$(dirname "$(git rev-parse --show-toplevel)")"

    for dir in "$parent/${project}-${agent}"-*/; do
        if [ -d "$dir" ]; then
            local n="${dir##*-}"
            n="${n%/}"
            case "$n" in
                "" | *[!0-9]*) continue ;;
            esac
            if [ "$n" -ge "$next_index" ]; then
                next_index=$((n + 1))
            fi
        fi
    done

    local wt_path="${parent}/${project}-${agent}-${next_index}"

    # Branch name
    local branch
    if [ -n "$task" ]; then
        local slug
        slug=$(printf '%s' "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-30)
        branch="wt/${agent}/${next_index}-${slug}"
    else
        branch="wt/${agent}/${next_index}"
    fi

    # Base ref
    if [ -z "$base" ]; then
        if git rev-parse --verify --quiet "origin/main" >/dev/null 2>&1; then
            base="origin/main"
        elif git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
            base="main"
        else
            base="HEAD"
        fi
    fi

    # Create worktree (reuse git_worktree_add for git-crypt safety)
    git_worktree_add "$wt_path" "$branch" "$base" || return 1

    # Log
    printf '[%s] SPAWN agent=%s index=%s path=%s branch=%s base=%s\n' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$agent" "$next_index" "$wt_path" "$branch" "$base" \
        >> "${git_common}/ai-worktree-spawn.log"

    ux_header "Worktree spawned"
    ux_info "  Path:   $wt_path"
    ux_info "  Branch: $branch"
    ux_info "  Base:   $base"

    # --- Optional tmux integration ---
    if [ "$use_tmux" = 1 ]; then
        _tmux_add_agent_window "$project" "$agent" "$wt_path"
        ux_info "  tmux:   session '$project', window '$agent'"
        if [ -z "$TMUX" ]; then
            tmux attach -t "$project"
        else
            tmux switch-client -t "${project}:${agent}" 2>/dev/null || true
        fi
    else
        ux_info ""
        ux_info "  cd $wt_path"
    fi
}

# ============================================================================
# Worktree teardown — remove worktree, sync main, delete branch, log
# Usage: git_worktree_teardown [--force] [--keep-branch]
# ============================================================================
git_worktree_teardown() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force=false keep_branch=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help|help)
                ux_header "gwt teardown - AI worktree cleanup"
                ux_info "Usage: gwt teardown [--force] [--keep-branch]"
                ux_info ""
                ux_info "Options:"
                ux_info "  --force        discard uncommitted changes and force remove"
                ux_info "  --keep-branch  keep the branch after removing worktree"
                return 0
                ;;
            --force) force=true; shift ;;
            --keep-branch) keep_branch=true; shift ;;
            *) ux_error "Unknown option: $1. Use --help for usage."; return 1 ;;
        esac
    done

    # Must be inside a worktree
    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        ux_error "Not inside a git repository"; return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" = "$git_common" ]; then
        ux_error "Not inside a worktree. Nothing to tear down."
        return 1
    fi

    # Pre-flight: uncommitted changes
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        if [ "$force" = true ]; then
            ux_warning "Discarding uncommitted changes (--force)"
        else
            ux_error "Uncommitted changes. Commit, stash, or use --force."
            return 1
        fi
    fi

    # Pre-flight: unpushed commits
    local local_rev remote_rev
    local_rev="$(git rev-parse HEAD)"
    remote_rev="$(git rev-parse '@{u}' 2>/dev/null || echo "no-upstream")"
    if [ "$remote_rev" != "no-upstream" ] && [ "$local_rev" != "$remote_rev" ]; then
        if [ "$force" = true ]; then
            ux_warning "Discarding unpushed commits (--force)"
        else
            ux_error "Unpushed commits. Push first, or use --force."
            return 1
        fi
    fi

    # Collect info before leaving
    local wt_path branch wt_name main_repo
    wt_path="$(git rev-parse --show-toplevel)"
    branch="$(git rev-parse --abbrev-ref HEAD)"
    wt_name="$(basename "$wt_path")"
    main_repo="$(dirname "$git_common")"

    # Switch to main repo
    cd "$main_repo" || { ux_error "Cannot cd to $main_repo"; return 1; }

    # Remove worktree
    if ! git worktree remove "$wt_path" 2>/dev/null; then
        if [ "$force" = true ]; then
            git worktree remove --force "$wt_path" || { ux_error "Failed to remove worktree"; return 1; }
        else
            ux_error "Cannot remove worktree. Use --force to override."
            return 1
        fi
    fi
    git worktree prune

    # Sync main BEFORE branch delete
    local main_branch="main"
    if ! git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
        main_branch="master"
    fi
    if ! git checkout "$main_branch" 2>/dev/null; then
        ux_error "Failed to checkout $main_branch in main repository."
        return 1
    fi
    git pull origin "$main_branch" 2>/dev/null || ux_warning "Pull failed (network?). Branch delete may misjudge merge status."

    # Delete branch
    if [ "$keep_branch" = true ]; then
        ux_info "Branch kept: $branch (--keep-branch)"
    elif git branch -d "$branch" 2>/dev/null; then
        : # deleted successfully
    elif [ "$force" = true ]; then
        git branch -D "$branch" 2>/dev/null
    else
        ux_warning "Branch '$branch' not fully merged. Use --force or --keep-branch."
    fi

    # Log
    printf '[%s] TEARDOWN worktree=%s branch=%s path=%s\n' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$wt_name" "$branch" "$wt_path" \
        >> "$(git rev-parse --git-common-dir)/ai-worktree-spawn.log"

    ux_success "Teardown complete"
    ux_info "  Removed: $wt_path"
    ux_info "  Now on:  $main_branch"
}

# ============================================================================
# Aliases
# ============================================================================
alias git-log='git_log'
alias gl='git-log'
alias git-log-upstream='git_log_upstream'
alias git-prune-remote='git_prune_remote'
alias git-clean-local='git_clean_local'
