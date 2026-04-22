#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_flow.sh
# gh-flow — fire-and-forget N-parallel GitHub issue → PR automation.
# Design: docs/feature/gh-flow-automation/design.md

# ============================================================================
# State helpers
# ============================================================================

_gh_flow_state_root() {
    printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/gh-flow"
}

_gh_flow_repo_name() {
    basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null
}

_gh_flow_issue_dir() {
    # $1 = issue number
    local _root _name
    _root=$(_gh_flow_state_root)
    _name=$(_gh_flow_repo_name)
    printf '%s/%s/%s' "$_root" "$_name" "$1"
}

_gh_flow_set_state() {
    # $1 = issue-dir path, $2 = state
    # Takes a dir (not an issue number) so callers inside a worktree are
    # not affected by cwd — otherwise _gh_flow_issue_dir recomputes via
    # `git rev-parse --show-toplevel` and silently writes to a different
    # location after the worker cd's into its worktree.
    mkdir -p "$1"
    printf '%s\n' "$2" >"$1/state"
}

_gh_flow_get_state() {
    # $1 = issue; prints state or "nonexistent"
    local _dir
    _dir=$(_gh_flow_issue_dir "$1")
    if [ -f "$_dir/state" ]; then
        cat "$_dir/state"
    else
        printf 'nonexistent'
    fi
}

# ============================================================================
# Help
# ============================================================================

gh_flow_help() {
    ux_header "gh-flow - fire-and-forget GitHub issue → PR automation"
    ux_info "Usage: gh-flow <issue-number>... | -h|--help"
    ux_info ""
    ux_info "Spawns one background worker per issue. Each worker:"
    ux_bullet "gwt spawn → /gh-issue-flow → poll reviews → /gh-pr-reply (once, if comments)"
    ux_bullet "→ poll for APPROVED → /gh-pr-merge → gwt teardown"
    ux_info ""
    ux_info "Examples:"
    ux_bullet "gh-flow 13                  # single issue"
    ux_bullet "gh-flow 13 42 88            # 3 issues in parallel"
    ux_info ""
    ux_info "State directory: ~/.local/state/gh-flow/<repo>/<issue>/"
    ux_bullet_sub "state         - current step"
    ux_bullet_sub "pid           - worker process id"
    ux_bullet_sub "worktree.path - git worktree path"
    ux_bullet_sub "pr.number     - PR number"
    ux_bullet_sub "reply.done    - marker (present if reply already ran)"
    ux_bullet_sub "log           - full stdout+stderr"
    ux_info ""
    ux_info "Failure isolation:"
    ux_bullet "One worker failure does not affect others."
    ux_bullet "Failed worker leaves worktree intact; state shows 'failed:<step>'."
    ux_info ""
    ux_info "Preconditions:"
    ux_bullet "Run from main repo (not inside a worktree)"
    ux_bullet "gh CLI authenticated, claude CLI on PATH, gwt loaded"
}

# ============================================================================
# Orchestrator
# ============================================================================

gh_flow() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1:-}" in
        ""|-h|--help|help)
            gh_flow_help
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
        ux_error "gh-flow must run from the main repo, not a worktree"
        ux_info "cd to the main repo and retry"
        return 1
    fi

    # Validate each arg is a positive integer
    local _issue
    for _issue in "$@"; do
        case "$_issue" in
            ''|*[!0-9]*)
                ux_error "invalid issue number: '$_issue' (must be positive integer)"
                return 1
                ;;
        esac
    done

    ux_header "gh-flow: spawning $# worker(s)"
    for _issue in "$@"; do
        _gh_flow_spawn_worker "$_issue"
    done
    ux_success "All workers detached. Your shell is free. Results will appear on the kanban."
}

_gh_flow_spawn_worker() {
    local _issue="$1"
    local _dir _log _state _pid
    _dir=$(_gh_flow_issue_dir "$_issue")
    mkdir -p "$_dir"
    _log="$_dir/log"

    # Idempotency check
    _state=$(_gh_flow_get_state "$_issue")
    case "$_state" in
        done)
            ux_info "#$_issue already done, skipping"
            return 0
            ;;
        spawning|implementing|polling|replying|merging|tearing-down)
            if [ -f "$_dir/pid" ]; then
                _pid="$(cat "$_dir/pid")"
                if kill -0 "$_pid" 2>/dev/null; then
                    ux_warning "#$_issue already running (pid=$_pid), skipping"
                    return 0
                fi
            fi
            ux_info "#$_issue was in-progress but pid is dead — resuming with a new worker"
            ;;
    esac

    # Rotate previous log (keep one .prev for debugging)
    if [ -f "$_log" ]; then
        mv "$_log" "$_log.prev" 2>/dev/null || true
    fi

    # Fork detached worker. DOTFILES_FORCE_INIT=1 forces full shell-common
    # loading in the non-interactive subshell so `gwt`, `ux_*`, and helpers
    # resolve. The subshell sources ~/.bashrc then calls _gh_flow_worker.
    # shellcheck disable=SC2016
    nohup env DOTFILES_FORCE_INIT=1 bash -c '
        . "$HOME/.bashrc" 2>/dev/null || true
        _gh_flow_worker "$1"
    ' -- "$_issue" >"$_log" 2>&1 &
    _pid=$!
    disown "$_pid" 2>/dev/null || true
    printf '%s\n' "$_pid" >"$_dir/pid"
    ux_info "#$_issue → pid=$_pid  log=$_log"
}

# ============================================================================
# Worker (runs in a detached bash subshell)
# ============================================================================

_gh_flow_worker() {
    local _issue="$1"
    local _dir _worktree _pr _spawn_name _decision _comments
    _dir=$(_gh_flow_issue_dir "$_issue")
    _spawn_name="issue-$_issue"

    printf '[gh-flow-worker] issue=#%s start=%s\n' "$_issue" "$(date -Iseconds 2>/dev/null || date)"

    # ---- Step 1: spawn worktree ----
    # Snapshot the worktree list before and after `gwt spawn` and diff them
    # to identify the new one. This avoids coupling to gwt's internal
    # branch-naming convention (previously: parsing `wt/<name>/<idx>`).
    local _wt_before _wt_after
    _gh_flow_set_state "$_dir" "spawning"
    _wt_before=$(git worktree list --porcelain 2>/dev/null | awk '$1=="worktree"{print $2}')
    if ! gwt spawn "$_spawn_name"; then
        _gh_flow_set_state "$_dir" "failed:spawning"
        printf '[gh-flow-worker] gwt spawn failed\n' >&2
        return 1
    fi

    _wt_after=$(git worktree list --porcelain 2>/dev/null | awk '$1=="worktree"{print $2}')
    _worktree=$(comm -13 \
        <(printf '%s\n' "$_wt_before" | sort) \
        <(printf '%s\n' "$_wt_after" | sort) \
        | head -n 1)

    if [ -z "$_worktree" ] || [ ! -d "$_worktree" ]; then
        _gh_flow_set_state "$_dir" "failed:spawning"
        printf '[gh-flow-worker] could not locate newly-created worktree\n' >&2
        return 1
    fi
    printf '%s\n' "$_worktree" >"$_dir/worktree.path"
    printf '[gh-flow-worker] worktree=%s\n' "$_worktree"

    # shellcheck disable=SC2164
    cd "$_worktree" || {
        _gh_flow_set_state "$_dir" "failed:spawning"
        return 1
    }

    # ---- Step 2: implement (claude runs /gh-issue-flow) ----
    _gh_flow_set_state "$_dir" "implementing"
    if ! claude --dangerously-skip-permissions -p "/gh-issue-flow $_issue"; then
        _gh_flow_set_state "$_dir" "failed:implementing"
        printf '[gh-flow-worker] /gh-issue-flow failed\n' >&2
        return 1
    fi

    _pr="$(gh pr view --json number --jq '.number' 2>/dev/null)"
    if [ -z "$_pr" ]; then
        _gh_flow_set_state "$_dir" "failed:implementing"
        printf '[gh-flow-worker] no PR created by /gh-issue-flow\n' >&2
        return 1
    fi
    printf '%s\n' "$_pr" >"$_dir/pr.number"
    printf '[gh-flow-worker] PR=#%s\n' "$_pr"

    # ---- Step 3: poll for review / approval ----
    _gh_flow_set_state "$_dir" "polling"
    while true; do
        sleep 60

        _decision="$(gh pr view "$_pr" --json reviewDecision --jq '.reviewDecision // ""' 2>/dev/null)"
        if [ "$_decision" = "APPROVED" ]; then
            printf '[gh-flow-worker] approved\n'
            break
        fi

        # Reply once, only if comments/changes-requested exist and we haven't replied yet.
        if [ ! -f "$_dir/reply.done" ]; then
            _comments="$(gh pr view "$_pr" --json reviews \
                --jq '[.reviews[] | select(.state == "COMMENTED" or .state == "CHANGES_REQUESTED")] | length' \
                2>/dev/null)"
            if [ -n "$_comments" ] && [ "$_comments" -gt 0 ]; then
                _gh_flow_set_state "$_dir" "replying"
                printf '[gh-flow-worker] running /gh-pr-reply (%s review(s))\n' "$_comments"
                if claude --dangerously-skip-permissions -p "/gh-pr-reply"; then
                    touch "$_dir/reply.done"
                    _gh_flow_set_state "$_dir" "polling"
                else
                    _gh_flow_set_state "$_dir" "failed:replying"
                    printf '[gh-flow-worker] /gh-pr-reply failed\n' >&2
                    return 1
                fi
            fi
        fi
    done

    # ---- Step 4: merge ----
    _gh_flow_set_state "$_dir" "merging"
    if ! claude --dangerously-skip-permissions -p "/gh-pr-merge"; then
        _gh_flow_set_state "$_dir" "failed:merging"
        printf '[gh-flow-worker] /gh-pr-merge failed\n' >&2
        return 1
    fi

    # ---- Step 5: teardown (must run inside the worktree) ----
    _gh_flow_set_state "$_dir" "tearing-down"
    if ! gwt teardown --force; then
        _gh_flow_set_state "$_dir" "failed:tearing-down"
        printf '[gh-flow-worker] gwt teardown failed\n' >&2
        return 1
    fi

    _gh_flow_set_state "$_dir" "done"
    printf '[gh-flow-worker] done issue=#%s end=%s\n' "$_issue" "$(date -Iseconds 2>/dev/null || date)"
}

# ============================================================================
# Aliases (hyphenated command names per shell-common convention)
# ============================================================================

alias gh-flow='gh_flow'
alias gh-flow-help='gh_flow_help'
