#!/bin/sh
# shell-common/functions/git_branch.sh
# Git branch management — feature-branch cleanup (gbr teardown)
# Mirrors shell-common/functions/git_worktree.sh (gwt) design for consistency.

# Override Oh My Zsh's `gbr` alias (zsh git plugin sets it to `git branch --remote`)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

unalias gbr 2>/dev/null || true

# ============================================================================
# gbr-help — compact help (canonical)
# Usage: gbr-help [section|--list|--all]
# ============================================================================
_gbr_help_summary() {
    ux_info "Usage: gbr-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "teardown: gbr teardown [--force] [--keep-branch] [--discard-changes]"
    ux_bullet_sub "details: gbr-help <section> (example: gbr-help teardown)"
}

_gbr_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "teardown"
}

_gbr_help_rows_teardown() {
    ux_table_row "syntax" "gbr teardown [--force] [--keep-branch] [--discard-changes]" "Cleanup merged feature branch"
    ux_table_row "context" "Run from the feature branch (not main, not worktree)" "Switches to main, pulls, deletes current branch"
    ux_table_row "signal" "Detects '[gone]' upstream as PR-merged" "Blocks otherwise; use --force to override"
    ux_table_row "flags" "--force / --keep-branch / --discard-changes" "Skip merge-status checks (non-destructive) / sync main only / DESTRUCTIVE overwrite of local changes"
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
        help)
            ux_error "Use canonical entrypoint: gbr-help (not 'gbr help')"
            ux_info "Try: gbr-help"
            return 1
            ;;
        -h|--help|"")
            [ $# -gt 0 ] && shift
            gbr_help "$@"
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

    local force=false keep_branch=false discard_changes=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help|help)
                ux_header "gbr teardown - feature branch cleanup after PR merge"
                ux_info "Usage: gbr teardown [--force] [--keep-branch] [--discard-changes]"
                ux_info ""
                ux_info "Concept: SELF-CLEANUP on the CURRENT branch."
                ux_info "  Stand on the branch, run teardown, land on main."
                ux_info ""
                ux_info "Options:"
                ux_info "  --force            proceed despite upstream-still-exists / not-fully-merged / dirty tree"
                ux_info "                     (NON-destructive: never overwrites local file contents)"
                ux_info "  --keep-branch      sync main only, keep the current branch"
                ux_info "  --discard-changes  DESTRUCTIVE: discard uncommitted/conflicted changes to force the switch"
                ux_info ""
                ux_info "Typical flow (single branch):"
                ux_bullet "gbr teardown                           # current branch, after PR merge"
                ux_info ""
                ux_info "Backlog of N merged PRs (order-independent):"
                ux_bullet "git checkout <br1> && gbr teardown   # auto-fetches refs"
                ux_bullet "git checkout <br2> && gbr teardown"
                ux_info ""
                ux_info "See also: 'gbr-help teardown' for the summary table."
                return 0
                ;;
            --force) force=true; shift ;;
            --keep-branch) keep_branch=true; shift ;;
            --discard-changes) discard_changes=true; shift ;;
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

    # Detect a merge-in-progress / unmerged index up front. A plain `git checkout`
    # later (Step "Switch to main") would refuse this with a split, opaque error —
    # the helpful header goes to stderr ("error: you need to resolve your current
    # index first") while only the cryptic "<file>: needs merge" reaches stdout.
    # Surface it here with actionable guidance instead. `--force` alone must NOT
    # bypass this: forcing the switch would silently destroy the conflicted files.
    local has_conflict=false
    if git rev-parse --verify --quiet MERGE_HEAD >/dev/null 2>&1 \
        || [ -n "$(git ls-files --unmerged 2>/dev/null)" ]; then
        has_conflict=true
    fi

    # Pre-flight: merge conflict / uncommitted changes
    if [ "$has_conflict" = true ]; then
        if [ "$discard_changes" = true ]; then
            ux_warning "Merge in progress / unmerged paths present (--discard-changes will overwrite them)"
        else
            ux_error "Merge in progress / unmerged paths — resolve before teardown."
            echo ""
            ux_info "The working tree has an unmerged index; a branch switch is blocked"
            ux_info "(git: 'you need to resolve your current index first')."
            echo ""
            ux_info "Pick one:"
            ux_bullet "git merge --abort                        # discard the in-progress merge"
            ux_bullet "resolve conflicts, then git add/commit   # keep the merge result"
            ux_bullet "git stash --include-untracked            # shelve for later"
            echo ""
            ux_warning "Plain --force does NOT bypass this (it would destroy your files)."
            ux_info "To intentionally discard local changes: gbr teardown --discard-changes"
            return 1
        fi
    elif ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        if [ "$discard_changes" = true ]; then
            ux_warning "Uncommitted changes present (--discard-changes)"
        elif [ "$force" = true ]; then
            ux_warning "Uncommitted changes present (--force)"
        else
            ux_error "Uncommitted changes. Commit, stash, or use --force."
            return 1
        fi
    fi

    # Auto-refresh remote tracking refs so `[gone]` is accurate.
    # Without this, a just-merged PR leaves stale `<remote>/<branch>` and the
    # upstream check below would reject with "PR not merged yet". Fail-soft:
    # offline sessions continue with whatever refs are cached locally.
    #
    # Remote is derived from the branch's own upstream (fork workflows may
    # track `upstream/<branch>` instead of `origin/<branch>`); fall back to
    # `origin` when no upstream is configured.
    local upstream_gone=false
    if [ "$force" != true ]; then
        local fetch_remote upstream_short
        upstream_short="$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)"
        fetch_remote="${upstream_short%%/*}"
        [ -z "$fetch_remote" ] && fetch_remote="origin"
        git fetch --prune --quiet "$fetch_remote" 2>/dev/null \
            || ux_warning "Fetch from '$fetch_remote' failed (offline?) — proceeding with stale refs."
    fi

    # Merge-safety gate — refuse to delete a branch whose work is NOT yet in
    # main, UNLESS --force. "Merged" is confirmed by ANY of three independent
    # signals; any one is enough:
    #
    #   S1  upstream is [gone]   — remote PR head was deleted (squash/rebase merge).
    #   S2  contained in main    — the branch tip is an ancestor of origin/main
    #                              (merge-commit or fast-forward merge). This is the
    #                              signal that saves branches whose upstream is the
    #                              BASE branch itself (e.g. a review/worktree branch
    #                              created off main and pushed under a DIFFERENT
    #                              remote name, #1108) — there [gone] can NEVER fire.
    #   S3  gh reports MERGED    — authoritative fallback when the branch name still
    #                              matches its own PR head ref.
    #
    # Use `%(upstream:short)` (not `@{u}`) to detect "was ever pushed", because
    # `@{u}` fails to resolve once the remote-tracking ref is pruned.
    local pr_merged=false contained=false
    if [ "$force" != true ]; then
        local upstream_ref upstream_track
        upstream_ref="$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)"
        upstream_track="$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)"

        # S1
        case "$upstream_track" in *gone*) upstream_gone=true ;; esac

        # S2 — prefer the remote-tracking main (freshest post-merge); fall back
        # to local main. Ancestry is reflexive, so an equal tip also counts.
        local main_ref=""
        if git rev-parse --verify --quiet "origin/$main_branch" >/dev/null 2>&1; then
            main_ref="origin/$main_branch"
        elif git rev-parse --verify --quiet "$main_branch" >/dev/null 2>&1; then
            main_ref="$main_branch"
        fi
        if [ -n "$main_ref" ] \
            && git merge-base --is-ancestor "$branch" "$main_ref" 2>/dev/null; then
            contained=true
        fi

        # S3 — best-effort PR lookup; also surfaces "#151 OPEN" in the blocked
        # message below. Silent on gh missing/unauthed. Use `.[]` (not `.[0]`) so
        # an empty array yields empty output, not "#null null  null".
        local pr_info=""
        if [ "$upstream_gone" != true ] && [ "$contained" != true ] \
            && command -v gh >/dev/null 2>&1; then
            pr_info="$(gh pr list --head "$branch" --state all --limit 1 \
                --json number,state,url \
                --jq '.[] | "#\(.number) \(.state)  \(.url)"' 2>/dev/null)"
            case "$pr_info" in *' MERGED '*) pr_merged=true ;; esac
        fi

        if [ "$upstream_gone" != true ] && [ "$contained" != true ] \
            && [ "$pr_merged" != true ]; then
            ux_error "Cannot tear down — PR not merged yet"
            echo ""
            ux_table_row "Branch" "$branch"
            ux_table_row "Upstream" "${upstream_ref:-<none — never pushed>}"
            ux_table_row "Track status" "${upstream_track:-up-to-date}"
            if [ -n "$pr_info" ]; then
                ux_table_row "Pull request" "$pr_info"
            fi
            echo ""
            ux_info "What to do next:"
            ux_bullet "Merge the PR on GitHub, then re-run: gbr teardown"
            ux_bullet "Or override the safety check: gbr teardown --force"
            return 1
        fi
    fi

    # Switch to main.
    #
    # With --discard-changes we explicitly force-overwrite the working tree
    # (`checkout -f`). Otherwise we use a plain checkout and SURFACE its stderr —
    # previously swallowed by `2>/dev/null` — so the real failure reason (e.g.
    # "you need to resolve your current index first") reaches the user instead of
    # a bare "Failed to checkout main."
    if [ "$discard_changes" = true ]; then
        if ! git checkout -f "$main_branch"; then
            ux_error "Failed to checkout $main_branch (even with --discard-changes)."
            return 1
        fi
        ux_warning "Discarded local changes to switch to $main_branch (--discard-changes)."
    else
        local checkout_err
        if ! checkout_err="$(git checkout "$main_branch" 2>&1 1>/dev/null)"; then
            ux_error "Failed to checkout $main_branch."
            [ -n "$checkout_err" ] && ux_info "git: $checkout_err"
            return 1
        fi
    fi

    # Sync main to origin — fetch + `git merge --ff-only`, matching
    # `gwt teardown` (git_worktree.sh:2308). `git pull` was wrong here: under
    # pull.rebase=false a diverged local main would silently gain an unwanted
    # merge commit, and under pull.rebase=true it rebases — neither is the
    # intended "catch up only if we cleanly can". Fast-forward only; a diverged
    # local main is reported with ahead/behind counts, never rewritten (#1125).
    if git fetch --quiet origin "$main_branch" 2>/dev/null; then
        if git rev-parse --verify --quiet "origin/$main_branch" >/dev/null 2>&1; then
            # Capture ff-only stderr (same as gwt teardown, git_worktree.sh:2312)
            # so a failure from uncommitted changes / an index lock surfaces its
            # real cause instead of being mislabeled as pure divergence.
            local _sync_err_file="${TMPDIR:-/tmp}/gbr-sync.$$.err"
            if ! git merge --ff-only "origin/$main_branch" 2>"$_sync_err_file" >/dev/null; then
                local _sync_ahead _sync_behind
                _sync_ahead="$(git rev-list --count "origin/$main_branch..$main_branch" 2>/dev/null || printf '?')"
                _sync_behind="$(git rev-list --count "$main_branch..origin/$main_branch" 2>/dev/null || printf '?')"
                ux_warning "Main sync skipped — local '$main_branch' diverged from origin/$main_branch (${_sync_ahead} ahead, ${_sync_behind} behind)."
                if [ -s "$_sync_err_file" ]; then
                    sed 's/^/    /' "$_sync_err_file" >&2
                fi
                ux_info "  Resolve manually (rebase / reset). Branch delete may misjudge merge status."
            fi
            rm -f "$_sync_err_file"
        fi
    else
        ux_warning "Fetch failed (network?). Branch delete may misjudge merge status."
    fi

    # Delete branch
    #
    # `git branch -d` only sees branches whose commits appear verbatim in main.
    # Squash/rebase merges rewrite the commits, so -d rejects them even though
    # the PR was merged. When upstream is `[gone]` we already know the PR
    # landed, so upgrade to -D without requiring --force.
    if [ "$keep_branch" = true ]; then
        ux_info "Branch kept: $branch (--keep-branch)"
    elif git branch -d "$branch" 2>/dev/null; then
        : # safe-deleted (merge-commit merge)
    elif [ "$force" = true ] || [ "$upstream_gone" = true ] || [ "$pr_merged" = true ]; then
        git branch -D "$branch" 2>/dev/null || {
            ux_error "Failed to force-delete branch '$branch'."
            return 1
        }
        if [ "$force" != true ] && { [ "$upstream_gone" = true ] || [ "$pr_merged" = true ]; }; then
            ux_info "Force-deleted (squash/rebase merge detected via merged PR)."
        fi
    else
        ux_warning "Branch '$branch' not fully merged into $main_branch. Use --force or --keep-branch."
        return 1
    fi

    ux_success "Teardown complete"
    ux_info "  Deleted: $branch"
    ux_info "  Now on:  $main_branch"
}

alias gbr-help='gbr_help'
