#!/bin/sh
# shell-common/functions/git_branch.sh
# Git branch management — feature-branch cleanup (gbr teardown)
# Mirrors shell-common/functions/git_worktree.sh (gwt) design for consistency.

# Override Oh My Zsh's `gbr` alias (zsh git plugin sets it to `git branch --remote`)
unalias gbr 2>/dev/null || true

# ============================================================================
# gbr-help — compact help (canonical)
# Usage: gbr-help [section|--list|--all]
# ============================================================================
_gbr_help_summary() {
    ux_info "Usage: gbr-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "teardown: gbr teardown [--force] [--keep-branch]"
    ux_bullet_sub "details: gbr-help <section> (example: gbr-help teardown)"
}

_gbr_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "teardown"
}

_gbr_help_rows_teardown() {
    ux_table_row "syntax" "gbr teardown [--force] [--keep-branch]" "Cleanup merged feature branch"
    ux_table_row "context" "Run from the feature branch (not main, not worktree)" "Switches to main, pulls, deletes current branch"
    ux_table_row "signal" "Detects '[gone]' upstream as PR-merged" "Blocks otherwise; use --force to override"
    ux_table_row "flags" "--force / --keep-branch" "Skip safety checks / sync main only"
}

_gbr_help_render_section() {
    ux_section "$1"
    "$2"
}

_gbr_help_section_rows() {
    case "$1" in
        teardown)
            _gbr_help_rows_teardown
            ;;
        *)
            ux_error "Unknown gbr-help section: $1"
            ux_info "Try: gbr-help --list"
            return 1
            ;;
    esac
}

_gbr_help_full() {
    ux_header "Git Branch Commands"
    _gbr_help_render_section "Teardown" _gbr_help_rows_teardown
}

gbr_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _gbr_help_summary
            ;;
        --list|list|section|sections)
            _gbr_help_list_sections
            ;;
        --all|all)
            _gbr_help_full
            ;;
        *)
            _gbr_help_section_rows "$1"
            ;;
    esac
}

# ============================================================================
# gbr — git branch dispatcher
# Usage: gbr <subcommand> [args...]
# ============================================================================
gbr() {
    case "${1:-}" in
        teardown) shift; git_branch_teardown "$@" ;;
        -h|--help|help|"")
            ux_error "Usage: gbr <command> [args...]"
            ux_info "Run: gbr-help"
            return 1
            ;;
        *)
            ux_error "Unknown command: $1"
            ux_info "Run: gbr-help"
            return 1
            ;;
    esac
}

# ============================================================================
# Branch teardown — feature-branch cleanup after PR merge
#   1. Switch to main
#   2. Pull origin main (fast-forward)
#   3. Delete the just-merged feature branch
#
# Usage: git_branch_teardown [--force] [--keep-branch]
# ============================================================================
git_branch_teardown() {
    # zsh compatibility: strict POSIX sh
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force=false keep_branch=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help|help)
                ux_header "gbr teardown - feature branch cleanup after PR merge"
                ux_info "Usage: gbr teardown [--force] [--keep-branch]"
                ux_info ""
                ux_info "Concept: SELF-CLEANUP on the CURRENT branch."
                ux_info "  Stand on the branch, run teardown, land on main."
                ux_info ""
                ux_info "Options:"
                ux_info "  --force        delete branch even if upstream still exists or not fully merged"
                ux_info "  --keep-branch  sync main only, keep the current branch"
                ux_info ""
                ux_info "Typical flow (single branch):"
                ux_bullet "gbr teardown                           # current branch, after PR merge"
                ux_info ""
                ux_info "Backlog of N merged PRs (order-independent):"
                ux_bullet "git fetch --prune"
                ux_bullet "git checkout <br1> && gbr teardown"
                ux_bullet "git checkout <br2> && gbr teardown"
                ux_info ""
                ux_info "See also: 'gbr-help teardown' for the summary table."
                return 0
                ;;
            --force) force=true; shift ;;
            --keep-branch) keep_branch=true; shift ;;
            -*)
                ux_error "Unknown option: $1. Use --help for usage."
                return 1
                ;;
            *)
                ux_error "'gbr teardown' does not accept a path argument."
                echo ""
                ux_info "This command is SELF-CLEANUP — it operates on the CURRENT branch."
                echo ""
                ux_info "Did you mean:"
                ux_bullet "git checkout \"$1\" && gbr teardown     # switch first, then cleanup"
                return 1
                ;;
        esac
    done

    # Must be in a git repo, NOT inside a worktree (worktree has gwt teardown)
    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        ux_error "Not inside a git repository"
        return 1
    }
    git_dir="$(git rev-parse --git-dir 2>/dev/null)"
    if [ "$git_dir" != "$git_common" ]; then
        ux_error "Inside a worktree — use 'gwt teardown' instead."
        echo ""
        ux_info "'gbr teardown' is for normal feature branches in the main repo."
        ux_info "'gwt teardown' cleans up worktrees (remove + sync main + delete branch)."
        return 1
    fi

    # Resolve current branch
    local branch
    branch="$(git symbolic-ref --short HEAD 2>/dev/null)" || {
        ux_error "Detached HEAD — nothing to tear down."
        return 1
    }

    # Determine main branch name (main preferred, master fallback)
    local main_branch="main"
    if ! git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
        main_branch="master"
    fi

    # Block if already on main/master
    if [ "$branch" = "$main_branch" ]; then
        ux_error "Already on '$main_branch' — nothing to tear down."
        echo ""
        ux_warning "'gbr teardown' deletes the CURRENT branch after syncing main."
        ux_warning "Running it on '$main_branch' itself would be destructive."
        echo ""
        ux_info "Did you mean:"
        ux_bullet "git checkout <feature-branch> && gbr teardown"
        return 1
    fi

    # Pre-flight: uncommitted changes
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        if [ "$force" = true ]; then
            ux_warning "Uncommitted changes present (--force)"
        else
            ux_error "Uncommitted changes. Commit, stash, or use --force."
            return 1
        fi
    fi

    # Upstream check — `[gone]` means remote branch was deleted (PR merge signal)
    if [ "$force" != true ]; then
        local upstream_ref upstream_track
        upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || upstream_ref=""
        upstream_track="$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)"

        if [ -z "$upstream_ref" ]; then
            ux_error "Branch '$branch' has no upstream — never pushed?"
            ux_info "Push and open a PR first, or use --force to delete anyway."
            return 1
        fi

        case "$upstream_track" in
            *gone*)
                : # expected: upstream deleted after PR merge
                ;;
            *)
                ux_error "Upstream '$upstream_ref' still exists — PR not merged yet?"
                ux_info "Track status: ${upstream_track:-up-to-date}"
                ux_info "Fetch first (git fetch --prune) or use --force to override."
                return 1
                ;;
        esac
    fi

    # Switch to main
    if ! git checkout "$main_branch" 2>/dev/null; then
        ux_error "Failed to checkout $main_branch."
        return 1
    fi

    # Pull main (fast-forward)
    if ! git pull origin "$main_branch"; then
        ux_warning "Pull failed (network?). Branch delete may misjudge merge status."
    fi

    # Delete branch
    if [ "$keep_branch" = true ]; then
        ux_info "Branch kept: $branch (--keep-branch)"
    elif git branch -d "$branch" 2>/dev/null; then
        : # safe-deleted
    elif [ "$force" = true ]; then
        git branch -D "$branch" 2>/dev/null || {
            ux_error "Failed to force-delete branch '$branch'."
            return 1
        }
    else
        ux_warning "Branch '$branch' not fully merged into $main_branch. Use --force or --keep-branch."
        return 1
    fi

    ux_success "Teardown complete"
    ux_info "  Deleted: $branch"
    ux_info "  Now on:  $main_branch"
}

alias gbr-help='gbr_help'
