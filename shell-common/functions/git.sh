#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/git.sh
# Git log, branch management, and utility functions

# Override Oh My Zsh's git aliases with our functions (zsh only)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

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

    # $branch and $saved_args are deliberately unquoted: both hold
    # space-separated argument lists that must split into separate git args.
    if [ $show_all -eq 1 ]; then
        # shellcheck disable=SC2086
        git log --graph --abbrev-commit --decorate=short --date=short \
            --pretty=format:"$fmt" $branch $saved_args
    else
        # shellcheck disable=SC2086
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
# gb — unified branch management dispatcher
# Usage: gb [-D local] [-D remote [<remote>]] [git-branch-flags...]
# ============================================================================
_gb_clean_remote() {
    # zsh compatibility: emulate POSIX sh to ensure word splitting on unquoted vars
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local assume_yes=0 include_others=0 remote=""

    # Parse optional flags and an optional remote name (order-independent)
    while [ $# -gt 0 ]; do
        case "$1" in
            -y | --yes) assume_yes=1 ;;
            --all) include_others=1 ;;
            -h | --help) _gb_help; return 0 ;;
            -*) ux_error "Unknown option: $1"; return 1 ;;
            *) remote="$1" ;;
        esac
        shift
    done
    remote="${remote:-origin}"

    # Fail fast if the remote is unknown
    if ! git remote get-url "$remote" >/dev/null 2>&1; then
        ux_error "Remote '$remote' not found"
        return 1
    fi

    # Sync tracking refs with the server so the deletion list is accurate
    git fetch --prune "$remote" >/dev/null 2>&1 || true

    # Ownership check: a branch is "mine" when its tip commit's author email
    # matches the local `git config user.email`. With no identity configured we
    # cannot claim anything, so every branch falls into the "others" bucket and
    # the safe default (delete nothing) applies.
    local my_email=""
    my_email=$(git config user.email 2>/dev/null) || my_email=""
    if [ -z "$my_email" ]; then
        ux_warning "git config user.email is unset — no branch can be identified as yours."
    fi

    # Build the deletable-branch lists with a pure-shell loop: one
    # `git for-each-ref` call yields branch name *and* author email together —
    # no per-branch subprocess forks. `case "$ref" in "$remote"/*)` matches the
    # remote name *literally* — a remote whose name contains a regex metachar
    # (e.g. '.') would mis-match under `grep "^$remote/"`. Emit short names (no
    # "<remote>/" prefix) — that is what `git push --delete` wants.
    # NOTE: unlike `git branch -r`, for-each-ref lists the symbolic
    # refs/remotes/<remote>/HEAD as a plain "origin/HEAD <email>" line with no
    # " -> " marker, so it must be skipped by name.
    # `mine` holds one branch per line; `others` holds "<branch> <email>". Both
    # accumulate with a leading newline (harmless — stripped once below) so the
    # append site needs no is-this-the-first-line branch.
    local nl="
"
    local mine="" others="" mine_count=0 other_count=0 ref email b
    while read -r ref email; do
        [ -n "$ref" ] || continue
        case "$ref" in
            "$remote"/*) b="${ref#"$remote"/}" ;;
            *) continue ;;
        esac
        [ "$b" = "HEAD" ] && continue
        [ "$b" = "main" ] && continue
        [ "$b" = "master" ] && continue
        # %(authoremail) renders as <user@example.com>
        email="${email#<}"
        email="${email%>}"
        if [ -n "$my_email" ] && [ "$email" = "$my_email" ]; then
            mine_count=$((mine_count + 1))
            mine="${mine}${nl}${b}"
        else
            other_count=$((other_count + 1))
            others="${others}${nl}${b} ${email}"
        fi
    done <<EOF
$(git for-each-ref --format='%(refname:short) %(authoremail)' "refs/remotes/$remote")
EOF
    mine="${mine#"$nl"}"
    others="${others#"$nl"}"

    if [ $((mine_count + other_count)) -eq 0 ]; then
        ux_info "No branches to delete on '$remote' (keeping main/master)"
        return 0
    fi

    if [ "$mine_count" -eq 0 ] && [ "$include_others" -ne 1 ]; then
        ux_info "No branches of yours to delete on '$remote' — skipped $other_count branch(es) owned by others (use --all to include them)."
        return 0
    fi

    # Deletion target = mine, plus others only when --all was given
    local include_all_others=0 branches="$mine" branch_count="$mine_count" line branch
    [ "$include_others" -eq 1 ] && [ "$other_count" -gt 0 ] && include_all_others=1
    if [ "$include_all_others" -eq 1 ]; then
        branch_count=$((mine_count + other_count))
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            b="${line%% *}"
            branches="${branches}${nl}${b}"
        done <<EOF
$others
EOF
        branches="${branches#"$nl"}"
    fi

    local warn_suffix=""
    [ "$include_all_others" -eq 1 ] && warn_suffix=", including OTHER PEOPLE'S branches"
    ux_warning "About to PERMANENTLY DELETE $branch_count branch(es) on remote '$remote'$warn_suffix:"

    if [ "$mine_count" -gt 0 ]; then
        ux_bullet "Your branches ($mine_count) — will be deleted:"
        while IFS= read -r branch; do
            [ -n "$branch" ] && ux_bullet_sub "$remote/$branch"
        done <<EOF
$mine
EOF
    fi

    if [ "$other_count" -gt 0 ]; then
        local others_label="Others' branches ($other_count) — skipped (use --all to include):"
        [ "$include_all_others" -eq 1 ] && others_label="Others' branches ($other_count) — will ALSO be deleted (--all):"
        ux_bullet "$others_label"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            b="${line%% *}"
            email="${line#* }"
            ux_bullet_sub "$remote/$b (author: $email)"
        done <<EOF
$others
EOF
    fi

    if [ "$assume_yes" -ne 1 ]; then
        if ! ux_confirm "Permanently delete these remote branches?"; then
            ux_info "Aborted. No branches deleted."
            return 0
        fi
    fi

    ux_header "Deleting $branch_count branch(es) from '$remote':"
    local deleted=0 failed=0
    while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        if git push "$remote" --delete "$branch" >/dev/null 2>&1; then
            ux_info "Deleted: $remote/$branch"
            deleted=$((deleted + 1))
        else
            ux_error "Failed: $remote/$branch"
            failed=$((failed + 1))
        fi
    done <<EOF
$branches
EOF

    if [ "$failed" -gt 0 ]; then
        ux_warning "Done with errors. Deleted $deleted, failed $failed."
        return 1
    fi
    ux_success "Done! Deleted $deleted branch(es) from '$remote'."
}

_gb_help() {
    ux_info "Usage: gb [-D local] [-D remote [-y] [--all] [<remote>]] [git-branch-flags...]"
    ux_bullet "sub-commands"
    ux_bullet_sub "gb -D local                              delete local branches (keeps: main + current + keywords)"
    ux_bullet_sub "gb -D remote [-y] [--all] [<remote>]     delete YOUR OWN branches on the remote SERVER (default: origin, e.g. origin, upstream, keeps: main/master; others' branches are listed but skipped unless --all)"
    ux_bullet_sub "gb [flags]                               passthrough to git --no-pager branch"
    ux_bullet "options"
    ux_bullet_sub "-y, --yes                 skip the confirmation prompt (remote deletion is permanent)"
    ux_bullet_sub "    --all                 also delete branches authored by other people (default: your own only, matched by git config user.email)"
}

git_branch() {
    case "${1:-}" in
        -D)
            case "${2:-}" in
                local)  shift 2; _gb_clean_local "$@" ;;
                remote) shift 2; _gb_clean_remote "$@" ;;
                *)
                    if [ $# -eq 2 ] && git remote get-url "$2" >/dev/null 2>&1 \
                        && ! git rev-parse --verify --quiet "refs/heads/$2" >/dev/null 2>&1; then
                        ux_error "No local branch named '$2' — '$2' is a remote, not a branch."
                        ux_info "Try: gb -D remote $2"
                        return 1
                    fi
                    git --no-pager branch "$@"
                    ;;
            esac
            ;;
        -h|--help|help)
            _gb_help ;;
        *)
            git --no-pager branch "$@" ;;
    esac
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
# Private sub-function: clean local branches (called via gb -D local)
# ============================================================================
_gb_clean_local() {
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

        if [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ "$branch" = "$current_branch" ]; then
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
# Aliases
# ============================================================================
alias git-log='git_log'
alias gl='git-log'
alias git-log-upstream='git_log_upstream'
alias gb='git_branch'
# Deprecated wrappers — prefer gb -D local / gb -D remote
alias git-clean-local='gb -D local'
alias gprune='gb -D remote'
alias git-prune-remote='gb -D remote'
