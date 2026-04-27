#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_reply.sh
# gh-pr-reply — fire-and-forget N-parallel GitHub PR review-reply runner.
# Sibling of gh-pr-approve (shell-common/functions/gh_pr_approve.sh) and
# gh-flow (shell-common/functions/gh_flow.sh); single-shot pipeline per
# PR: spawn worktree → run /gh-pr-reply → teardown.
#
# Key difference from gh-pr-approve: the /gh-pr-reply skill EDITS files
# (review-fix → commit → push). If the skill fails partway, unpushed
# local commits may remain in the worktree. To prevent data loss, this
# runner deliberately SKIPS teardown on skill failure and leaves the
# worktree intact for human recovery (see issue #198 Open Question —
# Option 1 chosen).

# ============================================================================
# State helpers
# ============================================================================

_gh_pr_reply_state_root() {
    printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/gh-pr-reply"
}

_gh_pr_reply_repo_name() {
    local _top
    _top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    basename "$_top"
}

_gh_pr_reply_pr_dir() {
    # $1 = PR number
    local _root _name
    _root=$(_gh_pr_reply_state_root)
    _name=$(_gh_pr_reply_repo_name)
    printf '%s/%s/%s' "$_root" "$_name" "$1"
}

_gh_pr_reply_set_state() {
    # $1 = pr-dir path, $2 = state
    # Takes a dir (not a PR number) so callers inside a worktree are not
    # affected by cwd — otherwise _gh_pr_reply_pr_dir recomputes via
    # `git rev-parse --show-toplevel` and silently writes elsewhere after
    # the worker cd's into its worktree.
    mkdir -p "$1"
    printf '%s\n' "$2" >"$1/state"
}

_gh_pr_reply_get_state() {
    # $1 = PR number; prints state or "nonexistent"
    local _dir
    _dir=$(_gh_pr_reply_pr_dir "$1")
    if [ -f "$_dir/state" ]; then
        cat "$_dir/state"
    else
        printf 'nonexistent'
    fi
}

# ============================================================================
# AI runner helpers
# ============================================================================
# Mirrors the contract introduced by `gh-flow --ai` (#208) so all three
# user-facing runners accept the same agent set with identical error UX.

# Validate the requested ai runner is supported and its CLI is on PATH.
_gh_pr_reply_require_ai_cli() {
    case "$1" in
        claude|codex|gemini)
            ux_require "$1" || return 1
            ;;
        *)
            ux_error "invalid --ai value: '$1' (expected: claude|codex|gemini)"
            return 1
            ;;
    esac
}

# Run one non-interactive prompt with the selected ai runner.
# Used by the worker to invoke /gh-pr-reply via the chosen CLI. Delegates
# to ai_usage.sh so each invocation appends a usage record (tokens,
# cost, duration) to <state-dir>/usage.jsonl, and the worker's tail-end
# _ai_usage_summary prints the totals.
_gh_pr_reply_run_ai_prompt() {
    local _ai="$1" _usage_log="$2" _label="$3" _prompt="$4"
    _ai_usage_run "$_ai" "$_usage_log" "$_label" "$_prompt"
}

# ============================================================================
# Help
# ============================================================================

gh_pr_reply_help() {
    ux_header "gh-pr-reply - fire-and-forget GitHub PR review-reply runner"
    ux_info "Usage: gh-pr-reply <pr-number>... [--ai <agent>] | -h|--help"
    ux_bullet_sub "agent: claude (default) | codex | gemini"
    ux_info ""
    ux_info "Spawns one background worker per PR. Each worker:"
    ux_bullet "gwt spawn → <ai> -p '/gh-pr-reply <N>' → gwt teardown"
    ux_info ""
    ux_info "The /gh-pr-reply skill edits files, commits, pushes, and replies"
    ux_info "to each review comment (Accepted or Declined). This runner only"
    ux_info "manages the worktree lifecycle around the skill."
    ux_info ""
    ux_info "Examples:"
    ux_bullet "gh-pr-reply 42                  # single PR (claude)"
    ux_bullet "gh-pr-reply 12 34 56            # 3 PRs in parallel"
    ux_bullet "gh-pr-reply '#42'               # '#' prefix accepted"
    ux_bullet "gh-pr-reply 33 --ai codex       # run worker with codex CLI"
    ux_bullet "gh-pr-reply --ai gemini 44 55   # run workers with gemini CLI"
    ux_info ""
    ux_info "State directory: ~/.local/state/gh-pr-reply/<repo>/<pr>/"
    ux_bullet_sub "state         - current step"
    ux_bullet_sub "pid           - worker process id"
    ux_bullet_sub "ai            - selected ai runner (claude|codex|gemini)"
    ux_bullet_sub "worktree.path - git worktree path"
    ux_bullet_sub "log           - full stdout+stderr"
    ux_bullet_sub "log.prev      - previous run's log (one generation)"
    ux_bullet_sub "usage.jsonl   - per-invocation token usage + cost (claude only)"
    ux_info ""
    ux_info "Failure isolation:"
    ux_bullet "One worker failure does not affect others."
    ux_bullet "On skill failure, teardown is SKIPPED and the worktree is"
    ux_bullet_sub "preserved so unpushed commits are not lost."
    ux_bullet_sub "state shows 'failed:<step>'; recover manually."
    ux_info ""
    ux_info "Preconditions:"
    ux_bullet "Run from main repo (not inside a worktree)"
    ux_bullet "gh CLI authenticated, selected AI CLI on PATH, gwt loaded"
    ux_info ""
    ux_info "Related:"
    ux_bullet "gh-flow         - issue → PR automation (author side)"
    ux_bullet "gh-pr-approve   - read-only LGTM/follow-up runner (reviewer side)"
    ux_bullet "/gh-pr-reply    - skill invoked inside the worker"
}

# ============================================================================
# Orchestrator
# ============================================================================

gh_pr_reply() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1:-}" in
        ""|-h|--help|help)
            gh_pr_reply_help
            return 0
            ;;
    esac

    # Parse optional args (PR numbers and --ai may interleave):
    #   --ai <claude|codex|gemini>
    #   --ai=<claude|codex|gemini>
    # Last --ai wins on duplicates — same policy gh-flow chose for #208.
    local _ai="claude"
    local _pr_args=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --ai)
                shift
                if [ $# -eq 0 ]; then
                    ux_error "--ai requires a value (expected: claude|codex|gemini)"
                    return 1
                fi
                _ai="$1"
                ;;
            --ai=*)
                _ai="${1#--ai=}"
                ;;
            -*)
                ux_error "unknown option: '$1'"
                ux_info "Usage: gh-pr-reply <pr-number>... [--ai <claude|codex|gemini>]"
                return 1
                ;;
            *)
                _pr_args="$_pr_args $1"
                ;;
        esac
        shift
    done

    # Restore PR args for downstream validation / spawn loop.
    # shellcheck disable=SC2086
    set -- $_pr_args
    if [ $# -eq 0 ]; then
        ux_error "no PR numbers provided"
        ux_info "Usage: gh-pr-reply <pr-number>... [--ai <claude|codex|gemini>]"
        return 1
    fi

    # Preconditions
    if ! _have git; then
        ux_error "git not found"
        return 1
    fi
    if ! _have gh; then
        ux_error "gh CLI not found"
        return 1
    fi
    if ! _gh_pr_reply_require_ai_cli "$_ai"; then
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
        ux_error "gh-pr-reply must run from the main repo, not a worktree"
        ux_info "cd to the main repo and retry"
        return 1
    fi

    # Validate each arg is a positive integer. Strip an optional leading '#'
    # so `gh-pr-reply '#42'` works the same as `gh-pr-reply 42` — same
    # ergonomic deviation gh-pr-approve makes, since PR numbers are
    # almost always written as #N in conversation.
    local _pr _pr_clean _pr_clean_args=""
    for _pr in "$@"; do
        _pr_clean="${_pr#\#}"
        case "$_pr_clean" in
            ''|*[!0-9]*)
                ux_error "invalid PR number: '$_pr' (must be positive integer, '#' prefix allowed)"
                return 1
                ;;
        esac
        _pr_clean_args="$_pr_clean_args $_pr_clean"
    done

    ux_header "gh-pr-reply: spawning $# worker(s) (ai=$_ai)"
    for _pr in $_pr_clean_args; do
        _gh_pr_reply_spawn_worker "$_pr" "$_ai"
    done
    ux_success "All workers detached. Your shell is free. Results appear on the PR."
}

_gh_pr_reply_spawn_worker() {
    local _pr="$1"
    local _ai="${2:-claude}"
    local _dir _log _state _pid
    _dir=$(_gh_pr_reply_pr_dir "$_pr")
    mkdir -p "$_dir"
    _log="$_dir/log"
    printf '%s\n' "$_ai" >"$_dir/ai"

    # Idempotency check — mirrors gh-pr-approve / gh-flow semantics.
    _state=$(_gh_pr_reply_get_state "$_pr")
    case "$_state" in
        done)
            ux_info "#$_pr already done, skipping"
            return 0
            ;;
        spawning|replying|tearing-down)
            if [ -f "$_dir/pid" ]; then
                _pid="$(cat "$_dir/pid")"
                if kill -0 "$_pid" 2>/dev/null; then
                    ux_warning "#$_pr already running (pid=$_pid), skipping"
                    return 0
                fi
            fi
            ux_info "#$_pr was in-progress but pid is dead — resuming with a new worker"
            ;;
        failed:*)
            # Don't auto-resume a failed run — the worktree may contain
            # unpushed commits. The user must inspect and clear state
            # explicitly. Mirrors how gh-flow's pr-reply step behaves.
            ux_warning "#$_pr previous run failed (state=$_state); inspect $_dir and worktree before retrying"
            ux_info "to retry: rm -rf $_dir   (after recovering any local commits)"
            return 0
            ;;
    esac

    # Rotate previous log (keep one .prev for debugging)
    if [ -f "$_log" ]; then
        mv "$_log" "$_log.prev" 2>/dev/null || true
    fi

    # Fork detached worker. DOTFILES_FORCE_INIT=1 forces full shell-common
    # loading in the non-interactive subshell so `gwt`, `ux_*`, and helpers
    # resolve. The subshell sources ~/.bashrc then calls _gh_pr_reply_worker.
    # shellcheck disable=SC2016
    nohup env DOTFILES_FORCE_INIT=1 bash -c '
        . "$HOME/.bashrc" 2>/dev/null || true
        _gh_pr_reply_worker "$1" "$2"
    ' -- "$_pr" "$_ai" >"$_log" 2>&1 &
    _pid=$!
    disown "$_pid" 2>/dev/null || true
    printf '%s\n' "$_pid" >"$_dir/pid"
    ux_info "#$_pr → pid=$_pid  ai=$_ai  log=$_log"
}

# ============================================================================
# Worker (runs in a detached bash subshell)
# ============================================================================

_gh_pr_reply_worker() {
    local _pr="$1"
    local _ai="${2:-claude}"
    local _dir _worktree _spawn_name _usage_log
    _dir=$(_gh_pr_reply_pr_dir "$_pr")
    _spawn_name="pr-$_pr"
    # Resolve the usage log path while still in the main repo: once we cd
    # into the worktree, _gh_pr_reply_pr_dir would point elsewhere.
    _usage_log="$_dir/usage.jsonl"
    : >"$_usage_log"

    printf '[gh-pr-reply-worker] pr=#%s ai=%s start=%s\n' "$_pr" "$_ai" "$(date -Iseconds 2>/dev/null || date)"

    # ---- Step 1: spawn worktree ----
    # Snapshot the worktree list before and after `gwt spawn` and diff them
    # to identify the new one. Same pattern as gh-flow / gh-pr-approve —
    # avoids coupling to gwt's internal branch-naming convention.
    local _wt_before _wt_after
    _gh_pr_reply_set_state "$_dir" "spawning"
    _wt_before=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    if ! gwt spawn "$_spawn_name"; then
        _gh_pr_reply_set_state "$_dir" "failed:spawning"
        printf '[gh-pr-reply-worker] gwt spawn failed\n' >&2
        return 1
    fi

    _wt_after=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    _worktree=$(comm -13 \
        <(printf '%s\n' "$_wt_before" | sort) \
        <(printf '%s\n' "$_wt_after" | sort) \
        | head -n 1)

    if [ -z "$_worktree" ] || [ ! -d "$_worktree" ]; then
        _gh_pr_reply_set_state "$_dir" "failed:spawning"
        printf '[gh-pr-reply-worker] could not locate newly-created worktree\n' >&2
        return 1
    fi
    printf '%s\n' "$_worktree" >"$_dir/worktree.path"
    printf '[gh-pr-reply-worker] worktree=%s\n' "$_worktree"

    # shellcheck disable=SC2164
    cd "$_worktree" || {
        _gh_pr_reply_set_state "$_dir" "failed:spawning"
        return 1
    }

    # ---- Step 2: reply (selected ai runs /gh-pr-reply <N>) ----
    # The skill is responsible for: review-comment fetch → evaluate → fix
    # files → commit → push → reply on each comment. The skill's exit
    # code is the source of truth for success/failure.
    #
    # CRITICAL: on failure we DO NOT teardown. The worktree may contain
    # local commits that were never pushed (e.g. push step failed mid-skill);
    # tearing down would permanently delete them. State is left as
    # 'failed:replying' for human recovery (#198 Open Question — Option 1).
    # The data-loss policy is invariant across ai runners.
    _gh_pr_reply_set_state "$_dir" "replying"
    if ! _gh_pr_reply_run_ai_prompt "$_ai" "$_usage_log" "/gh-pr-reply $_pr" "/gh-pr-reply $_pr"; then
        _gh_pr_reply_set_state "$_dir" "failed:replying"
        printf '[gh-pr-reply-worker] /gh-pr-reply failed — worktree preserved at %s for recovery\n' "$_worktree" >&2
        # Print usage even on failure so the user can correlate quota
        # spend with the recovery worktree they're about to inspect.
        _ai_usage_summary "$_usage_log" "Token Usage (PR #$_pr — failed)"
        return 1
    fi

    # ---- Step 3: teardown (must run inside the worktree) ----
    # The skill has already pushed any commits it created, so the
    # worktree is safe to remove. Only reached on a clean skill exit.
    _gh_pr_reply_set_state "$_dir" "tearing-down"
    if ! gwt teardown --force; then
        _gh_pr_reply_set_state "$_dir" "failed:tearing-down"
        printf '[gh-pr-reply-worker] gwt teardown failed\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (PR #$_pr — teardown failed)"
        return 1
    fi

    _gh_pr_reply_set_state "$_dir" "done"
    printf '[gh-pr-reply-worker] done pr=#%s end=%s\n' "$_pr" "$(date -Iseconds 2>/dev/null || date)"
    _ai_usage_summary "$_usage_log" "Token Usage (PR #$_pr)"
}

# ============================================================================
# Aliases (hyphenated command names per shell-common convention)
# ============================================================================

alias gh-pr-reply='gh_pr_reply'
alias gh-pr-reply-help='gh_pr_reply_help'
