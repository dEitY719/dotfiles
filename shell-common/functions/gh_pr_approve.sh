#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_approve.sh
# gh-pr-approve — fire-and-forget N-parallel GitHub PR approval runner.
# Sibling of gh-flow (shell-common/functions/gh_flow.sh); single-shot
# pipeline per PR: spawn worktree → run /gh-pr-approve → teardown.

# ============================================================================
# State helpers
# ============================================================================

_gh_pr_approve_state_root() {
    printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/gh-pr-approve"
}

_gh_pr_approve_repo_name() {
    basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null
}

_gh_pr_approve_pr_dir() {
    # $1 = PR number
    local _root _name
    _root=$(_gh_pr_approve_state_root)
    _name=$(_gh_pr_approve_repo_name)
    printf '%s/%s/%s' "$_root" "$_name" "$1"
}

_gh_pr_approve_set_state() {
    # $1 = pr-dir path, $2 = state
    # Takes a dir (not a PR number) so callers inside a worktree are not
    # affected by cwd — otherwise _gh_pr_approve_pr_dir recomputes via
    # `git rev-parse --show-toplevel` and silently writes elsewhere after
    # the worker cd's into its worktree.
    mkdir -p "$1"
    printf '%s\n' "$2" >"$1/state"
}

_gh_pr_approve_get_state() {
    # $1 = PR number; prints state or "nonexistent"
    local _dir
    _dir=$(_gh_pr_approve_pr_dir "$1")
    if [ -f "$_dir/state" ]; then
        cat "$_dir/state"
    else
        printf 'nonexistent'
    fi
}

# ============================================================================
# Help
# ============================================================================

gh_pr_approve_help() {
    ux_header "gh-pr-approve - fire-and-forget GitHub PR approval runner"
    ux_info "Usage: gh-pr-approve <pr-number>... | -h|--help"
    ux_info ""
    ux_info "Spawns one background worker per PR. Each worker:"
    ux_bullet "gwt spawn → claude -p '/gh-pr-approve <N>' → gwt teardown"
    ux_info ""
    ux_info "Examples:"
    ux_bullet "gh-pr-approve 42                # single PR"
    ux_bullet "gh-pr-approve 12 34 56          # 3 PRs in parallel"
    ux_info ""
    ux_info "State directory: ~/.local/state/gh-pr-approve/<repo>/<pr>/"
    ux_bullet_sub "state         - current step"
    ux_bullet_sub "pid           - worker process id"
    ux_bullet_sub "worktree.path - git worktree path"
    ux_bullet_sub "log           - full stdout+stderr"
    ux_bullet_sub "log.prev      - previous run's log (one generation)"
    ux_info ""
    ux_info "Failure isolation:"
    ux_bullet "One worker failure does not affect others."
    ux_bullet "Failed worker leaves worktree intact; state shows 'failed:<step>'."
    ux_info ""
    ux_info "Preconditions:"
    ux_bullet "Run from main repo (not inside a worktree)"
    ux_bullet "gh CLI authenticated, claude CLI on PATH, gwt loaded"
    ux_info ""
    ux_info "Related:"
    ux_bullet "gh-flow         - issue → PR automation (author side)"
    ux_bullet "/gh-pr-approve  - skill invoked inside the worker"
}

# ============================================================================
# Orchestrator
# ============================================================================

gh_pr_approve() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1:-}" in
        ""|-h|--help|help)
            gh_pr_approve_help
            return 0
            ;;
    esac

    # Preconditions
    if ! _have git; then
        ux_error "git not found"
        return 1
    fi
    if ! _have gh; then
        ux_error "gh CLI not found"
        return 1
    fi
    if ! _have claude; then
        ux_error "claude CLI not found"
        return 1
    fi
    if ! command -v gwt >/dev/null 2>&1; then
        ux_error "gwt function not loaded (source shell-common first)"
        return 1
    fi

    # Must be in main repo (not a worktree)
    local _git_dir _git_common
    _git_dir="$(git rev-parse --git-dir 2>/dev/null)"
    _git_common="$(git rev-parse --git-common-dir 2>/dev/null)"
    if [ -z "$_git_dir" ]; then
        ux_error "not inside a git repo"
        return 1
    fi
    if [ "$_git_dir" != "$_git_common" ]; then
        ux_error "gh-pr-approve must run from the main repo, not a worktree"
        ux_info "cd to the main repo and retry"
        return 1
    fi

    # Validate each arg is a positive integer. Strip an optional leading '#'
    # so `gh-pr-approve '#42'` works the same as `gh-pr-approve 42` — this is
    # a deliberate ergonomic deviation from gh-flow, since PR numbers are
    # almost always written as #N in conversation.
    local _pr _pr_clean _pr_args=""
    for _pr in "$@"; do
        _pr_clean="${_pr#\#}"
        case "$_pr_clean" in
            ''|*[!0-9]*)
                ux_error "invalid PR number: '$_pr' (must be positive integer, '#' prefix allowed)"
                return 1
                ;;
        esac
        _pr_args="$_pr_args $_pr_clean"
    done

    ux_header "gh-pr-approve: spawning $# worker(s)"
    for _pr in $_pr_args; do
        _gh_pr_approve_spawn_worker "$_pr"
    done
    ux_success "All workers detached. Your shell is free. Results appear on the PR."
}

_gh_pr_approve_spawn_worker() {
    local _pr="$1"
    local _dir _log _state _pid
    _dir=$(_gh_pr_approve_pr_dir "$_pr")
    mkdir -p "$_dir"
    _log="$_dir/log"

    # Idempotency check — mirrors gh-flow semantics.
    _state=$(_gh_pr_approve_get_state "$_pr")
    case "$_state" in
        done)
            ux_info "#$_pr already done, skipping"
            return 0
            ;;
        spawning|approving|tearing-down)
            if [ -f "$_dir/pid" ]; then
                _pid="$(cat "$_dir/pid")"
                if kill -0 "$_pid" 2>/dev/null; then
                    ux_warning "#$_pr already running (pid=$_pid), skipping"
                    return 0
                fi
            fi
            ux_info "#$_pr was in-progress but pid is dead — resuming with a new worker"
            ;;
    esac

    # Rotate previous log (keep one .prev for debugging)
    if [ -f "$_log" ]; then
        mv "$_log" "$_log.prev" 2>/dev/null || true
    fi

    # Fork detached worker. DOTFILES_FORCE_INIT=1 forces full shell-common
    # loading in the non-interactive subshell so `gwt`, `ux_*`, and helpers
    # resolve. The subshell sources ~/.bashrc then calls _gh_pr_approve_worker.
    # shellcheck disable=SC2016
    nohup env DOTFILES_FORCE_INIT=1 bash -c '
        . "$HOME/.bashrc" 2>/dev/null || true
        _gh_pr_approve_worker "$1"
    ' -- "$_pr" >"$_log" 2>&1 &
    _pid=$!
    disown "$_pid" 2>/dev/null || true
    printf '%s\n' "$_pid" >"$_dir/pid"
    ux_info "#$_pr → pid=$_pid  log=$_log"
}

# ============================================================================
# Worker (runs in a detached bash subshell)
# ============================================================================

_gh_pr_approve_worker() {
    local _pr="$1"
    local _dir _worktree _spawn_name
    _dir=$(_gh_pr_approve_pr_dir "$_pr")
    _spawn_name="pr-$_pr"

    printf '[gh-pr-approve-worker] pr=#%s start=%s\n' "$_pr" "$(date -Iseconds 2>/dev/null || date)"

    # ---- Step 1: spawn worktree ----
    # Snapshot the worktree list before and after `gwt spawn` and diff them
    # to identify the new one. Same pattern as gh-flow — avoids coupling to
    # gwt's internal branch-naming convention.
    local _wt_before _wt_after
    _gh_pr_approve_set_state "$_dir" "spawning"
    _wt_before=$(git worktree list --porcelain 2>/dev/null | awk '$1=="worktree"{print $2}')
    if ! gwt spawn "$_spawn_name"; then
        _gh_pr_approve_set_state "$_dir" "failed:spawning"
        printf '[gh-pr-approve-worker] gwt spawn failed\n' >&2
        return 1
    fi

    _wt_after=$(git worktree list --porcelain 2>/dev/null | awk '$1=="worktree"{print $2}')
    _worktree=$(comm -13 \
        <(printf '%s\n' "$_wt_before" | sort) \
        <(printf '%s\n' "$_wt_after" | sort) \
        | head -n 1)

    if [ -z "$_worktree" ] || [ ! -d "$_worktree" ]; then
        _gh_pr_approve_set_state "$_dir" "failed:spawning"
        printf '[gh-pr-approve-worker] could not locate newly-created worktree\n' >&2
        return 1
    fi
    printf '%s\n' "$_worktree" >"$_dir/worktree.path"
    printf '[gh-pr-approve-worker] worktree=%s\n' "$_worktree"

    # shellcheck disable=SC2164
    cd "$_worktree" || {
        _gh_pr_approve_set_state "$_dir" "failed:spawning"
        return 1
    }

    # ---- Step 2: approve (claude runs /gh-pr-approve <N>) ----
    # Single-shot. The skill either approves with LGTM or files follow-up
    # issues and exits. No polling, no reply loop — that's gh-flow's job.
    _gh_pr_approve_set_state "$_dir" "approving"
    if ! claude --dangerously-skip-permissions -p "/gh-pr-approve $_pr"; then
        _gh_pr_approve_set_state "$_dir" "failed:approving"
        printf '[gh-pr-approve-worker] /gh-pr-approve failed\n' >&2
        return 1
    fi

    # ---- Step 3: teardown (must run inside the worktree) ----
    # The skill is read-only (no file edits); worktree has nothing to push
    # and can be torn down immediately after the review is submitted.
    _gh_pr_approve_set_state "$_dir" "tearing-down"
    if ! gwt teardown --force; then
        _gh_pr_approve_set_state "$_dir" "failed:tearing-down"
        printf '[gh-pr-approve-worker] gwt teardown failed\n' >&2
        return 1
    fi

    _gh_pr_approve_set_state "$_dir" "done"
    printf '[gh-pr-approve-worker] done pr=#%s end=%s\n' "$_pr" "$(date -Iseconds 2>/dev/null || date)"
}

# ============================================================================
# Aliases (hyphenated command names per shell-common convention)
# ============================================================================

alias gh-pr-approve='gh_pr_approve'
alias gh-pr-approve-help='gh_pr_approve_help'
