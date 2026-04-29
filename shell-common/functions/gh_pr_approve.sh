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
# AI runner helpers (mirror gh_flow.sh — keep both modules in sync)
# ============================================================================

# Returns 0 if the ai runner is one of: claude, codex, gemini.
_gh_pr_approve_known_ai() {
    case "$1" in
    claude | codex | gemini) return 0 ;;
    *) return 1 ;;
    esac
}

# Ensure the selected ai CLI exists in PATH.
_gh_pr_approve_require_ai_cli() {
    case "$1" in
    claude)
        if ! _have claude; then
            ux_error "claude CLI not found"
            return 1
        fi
        ;;
    codex)
        if ! _have codex; then
            ux_error "codex CLI not found"
            return 1
        fi
        ;;
    gemini)
        if ! _have gemini; then
            ux_error "gemini CLI not found"
            return 1
        fi
        ;;
    *)
        ux_error "invalid --ai value: '$1' (allowed: claude, codex, gemini)"
        return 1
        ;;
    esac
}

# Run one non-interactive prompt with the selected ai runner.
# Delegates to ai_usage.sh so per-call token usage and cost are appended
# to <state-dir>/usage.jsonl. The worker tail-prints _ai_usage_summary,
# which is what made the "100% of MAX quota in 10 minutes" incident
# previously invisible — every claude `-p` session on a 1M-context Opus
# default model creates ~33k cache tokens (~$0.20) just to start.
_gh_pr_approve_run_ai_prompt() {
    local _ai="$1" _usage_log="$2" _label="$3" _prompt="$4"
    _ai_usage_run "$_ai" "$_usage_log" "$_label" "$_prompt"
}

# ============================================================================
# Verdict + PR-state helpers (used by status / prune)
# ============================================================================

# Echo a single line describing GitHub-side PR state for the entry whose
# state-dir is $1. Format:
#   <state>|<reviewDecision>|<date>
# or the literal token UNREACHABLE if the gh CLI call fails.
#
# - <state>: OPEN | MERGED | CLOSED (per gh pr view --json state)
# - <reviewDecision>: APPROVED | CHANGES_REQUESTED | REVIEW_REQUIRED |
#   COMMENTED | "" (gh returns empty when no review yet)
# - <date>: YYYY-MM-DD if MERGED/CLOSED, else empty
#
# This is a single gh pr view call. Verdict does NOT use this — it's purely
# informational for `status <N>` (per issue #268). Verdict stays decoupled
# from network state because the worker is single-shot: PR closure/merge
# is unrelated to whether the local worker still has cleanup to do.
_gh_pr_approve_pr_state() {
    local _dir="$1"
    local _pr_num _json _rc _state _decision _merged _closed _date
    _pr_num="$(basename "$_dir")"
    case "$_pr_num" in
    '' | *[!0-9]*)
        printf 'UNREACHABLE'
        return 0
        ;;
    esac
    _json="$(gh pr view "$_pr_num" --json state,reviewDecision,mergedAt,closedAt 2>/dev/null)"
    _rc=$?
    if [ "$_rc" -ne 0 ] || [ -z "$_json" ]; then
        printf 'UNREACHABLE'
        return 0
    fi
    # Note: outer "$(...)" intentionally omitted — POSIX sh does not
    # word-split bare assignments, and a project pre-commit naming check
    # heuristically flags any private-helper name that appears between two
    # `"` on a single line as user-facing text.
    _state=$(printf '%s' "$_json" | _gh_pr_approve_jq_field state)
    _decision=$(printf '%s' "$_json" | _gh_pr_approve_jq_field reviewDecision)
    _merged=$(printf '%s' "$_json" | _gh_pr_approve_jq_field mergedAt)
    _closed=$(printf '%s' "$_json" | _gh_pr_approve_jq_field closedAt)
    case "$_state" in
    MERGED) _date="${_merged%%T*}" ;;
    CLOSED) _date="${_closed%%T*}" ;;
    *) _date="" ;;
    esac
    printf '%s|%s|%s' "$_state" "$_decision" "$_date"
}

# Pull a single field's plain string out of a gh `--json …` payload using
# whichever JSON parser is on PATH. Mirrors the helper pattern used by
# gh_flow.sh and keeps the gh dependency soft (no jq required).
_gh_pr_approve_jq_field() {
    local _field="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r ".$_field? // empty" 2>/dev/null
    else
        # Naive fallback: grep the "field":"value" pair. Good enough for
        # the simple top-level fields we read from `gh pr view`.
        sed -n "s/.*\"$_field\":\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
    fi
}

# Print two lines for the given PR:
#   <verdict-text>
#   <next-action-text>
# Reads <pr-dir>/state, /pid, /worktree.path, then composes the matrix
# from the issue spec. gh-pr-approve's worker is single-shot (no polling,
# no reply loop), so the matrix is strictly simpler than gh-flow's.
_gh_pr_approve_verdict() {
    local _pr="$1"
    local _dir _state _wt _pid _pid_alive _verdict _action
    _dir=$(_gh_pr_approve_pr_dir "$_pr")
    if [ ! -d "$_dir" ]; then
        printf 'no state — PR not tracked\n(none)\n'
        return 0
    fi
    _state="$(cat "$_dir/state" 2>/dev/null || printf 'unknown')"
    _wt="$(cat "$_dir/worktree.path" 2>/dev/null || printf '')"
    _pid="$(cat "$_dir/pid" 2>/dev/null || printf '')"
    _pid_alive=0
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        _pid_alive=1
    fi

    case "$_state" in
    done)
        _verdict="done — safe to prune"
        _action="gh-pr-approve prune $_pr"
        ;;
    failed:*)
        if [ -n "$_wt" ] && [ -d "$_wt" ]; then
            _verdict="dead failure, worktree alive"
            _action="cd $_wt && gwt teardown --force, then gh-pr-approve prune $_pr"
        else
            _verdict="dead failure — state-only cleanup"
            _action="gh-pr-approve prune $_pr"
        fi
        ;;
    spawning | approving | tearing-down)
        if [ "$_pid_alive" = "1" ]; then
            _verdict="active worker ($_state) — leave alone"
            _action="(none — still working)"
        else
            _verdict="dead worker mid-step ($_state)"
            _action="gh-pr-approve prune $_pr"
        fi
        ;;
    *)
        _verdict="unknown state ($_state)"
        _action="inspect $_dir"
        ;;
    esac

    printf '%s\n%s\n' "$_verdict" "$_action"
}

# ============================================================================
# status / prune subcommands
# ============================================================================

# Per-PR diagnostic. Renders header + State/Worker/PR/Worktree/Flags/
# Last log (+ tail -5) + Verdict / Next action (via _gh_pr_approve_verdict).
# Input: <pr-num> with optional leading '#'.
_gh_pr_approve_status_single() {
    local _arg="$1"
    local _pr _dir _state _pid _wt _pid_state _wt_state
    local _pr_state_raw _pr_state _pr_decision _pr_date _pr_info
    local _flags _flags_state _log _log_mtime _etime
    local _verdict_out _verdict_text _action_text _name

    _pr="${_arg#\#}"
    case "$_pr" in
    '' | *[!0-9]*)
        ux_error "gh-pr-approve status: invalid PR number '$_arg'"
        return 1
        ;;
    esac

    _name=$(_gh_pr_approve_repo_name)
    if [ -z "$_name" ]; then
        ux_error "gh-pr-approve status: not inside a git repo"
        return 1
    fi

    _dir=$(_gh_pr_approve_pr_dir "$_pr")
    ux_header "gh-pr-approve status #$_pr - $_name"
    if [ ! -d "$_dir" ]; then
        ux_warning "no state for #$_pr in $_name (worker never ran or already pruned)"
        return 0
    fi

    _state="$(cat "$_dir/state" 2>/dev/null || printf 'unknown')"
    _pid="$(cat "$_dir/pid" 2>/dev/null || printf '')"
    _wt="$(cat "$_dir/worktree.path" 2>/dev/null || printf '')"

    # Worker liveness with elapsed time (etime= is "[[DD-]HH:]MM:SS" on Linux).
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        _etime="$(ps -p "$_pid" -o etime= 2>/dev/null | tr -d ' ')"
        if [ -n "$_etime" ]; then
            _pid_state="pid=$_pid (alive, $_etime)"
        else
            _pid_state="pid=$_pid (alive)"
        fi
    elif [ -n "$_pid" ]; then
        _pid_state="pid=$_pid (dead)"
    else
        _pid_state="-"
    fi

    # PR detail: single gh pr view call, includes reviewDecision and date.
    _pr_state_raw=$(_gh_pr_approve_pr_state "$_dir")
    if [ "$_pr_state_raw" = "UNREACHABLE" ]; then
        _pr_info="#$_pr (unreachable — gh CLI failed)"
    else
        _pr_state="${_pr_state_raw%%|*}"
        _pr_decision="${_pr_state_raw#*|}"
        _pr_date="${_pr_decision#*|}"
        _pr_decision="${_pr_decision%%|*}"
        if [ -z "$_pr_state" ]; then
            _pr_info="#$_pr (state unknown)"
        else
            _pr_info="#$_pr ($_pr_state"
            if [ -n "$_pr_decision" ]; then
                _pr_info="$_pr_info, review: $_pr_decision"
            fi
            if [ -n "$_pr_date" ]; then
                _pr_info="$_pr_info, $_pr_date"
            fi
            _pr_info="$_pr_info)"
        fi
    fi

    # Worktree presence.
    if [ -n "$_wt" ]; then
        if [ -d "$_wt" ]; then
            _wt_state="$_wt (present)"
        else
            _wt_state="$_wt (absent)"
        fi
    else
        _wt_state="(none)"
    fi

    # Flags recorded at spawn (only present when --self-record / --admin-merge
    # were passed). Trim whitespace so a stray newline does not look weird.
    if [ -f "$_dir/flags" ]; then
        _flags="$(tr -d '\n' <"$_dir/flags" 2>/dev/null | sed 's/^ *//; s/ *$//')"
        if [ -n "$_flags" ]; then
            _flags_state="$_flags"
        else
            _flags_state="(none)"
        fi
    else
        _flags_state="(none)"
    fi

    ux_table_row "State" "$_state"
    ux_table_row "Worker" "$_pid_state"
    ux_table_row "PR" "$_pr_info"
    ux_table_row "Worktree" "$_wt_state"
    ux_table_row "Flags" "$_flags_state"

    _log="$_dir/log"
    if [ -f "$_log" ]; then
        _log_mtime="$(date -r "$_log" '+%Y-%m-%d %H:%M' 2>/dev/null)"
        if [ -n "$_log_mtime" ]; then
            ux_table_row "Last log" "$_log_mtime"
        else
            ux_table_row "Last log" "$_log"
        fi
        printf '\n  --- tail -5 %s ---\n' "$_log"
        tail -n 5 "$_log" 2>/dev/null | sed 's/^/  /'
        printf '  ---\n'
    else
        ux_table_row "Last log" "(none)"
    fi

    # Heredoc (not pipe) so reads land in this shell — see auto-memory:
    # subshell tracing trap.
    _verdict_out=$(_gh_pr_approve_verdict "$_pr")
    {
        IFS= read -r _verdict_text || _verdict_text=""
        IFS= read -r _action_text || _action_text=""
    } <<EOF
$_verdict_out
EOF

    ux_info ""
    ux_table_row "Verdict" "$_verdict_text"
    ux_table_row "Next action" "$_action_text"
}

# List all known gh-pr-approve entries for the current repo, OR diagnose a
# single PR if exactly one positional arg is given. Multiple positional args
# are rejected (single-PR diagnostic only).
_gh_pr_approve_status() {
    if [ $# -gt 1 ]; then
        ux_error "gh-pr-approve status: only one PR number accepted (got $#)"
        return 1
    fi
    if [ -n "${1:-}" ]; then
        _gh_pr_approve_status_single "$1"
        return $?
    fi

    local _root _name _repo_dir _entry _pr _state _pid _wt _pid_state
    _root=$(_gh_pr_approve_state_root)
    _name=$(_gh_pr_approve_repo_name)
    if [ -z "$_name" ]; then
        ux_error "gh-pr-approve status: not inside a git repo"
        return 1
    fi
    _repo_dir="$_root/$_name"

    ux_header "gh-pr-approve status - $_name"
    if [ ! -d "$_repo_dir" ]; then
        ux_info "no state — no workers have ever run in this repo"
        return 0
    fi

    local _found=0
    ux_table_header "PR" "STATE" "PID / WORKTREE"
    for _entry in "$_repo_dir"/*/; do
        [ -d "$_entry" ] || continue
        _pr="$(basename "$_entry")"
        _state="$(cat "$_entry/state" 2>/dev/null || printf 'unknown')"
        _pid="$(cat "$_entry/pid" 2>/dev/null || printf '')"
        _wt="$(cat "$_entry/worktree.path" 2>/dev/null || printf '')"

        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            _pid_state="pid=$_pid (alive)"
        elif [ -n "$_pid" ]; then
            _pid_state="pid=$_pid (dead)"
        else
            _pid_state="-"
        fi

        if [ -n "$_wt" ]; then
            ux_table_row "#$_pr" "$_state" "$_pid_state  $_wt"
        else
            ux_table_row "#$_pr" "$_state" "$_pid_state"
        fi
        _found=1
    done
    if [ "$_found" = "0" ]; then
        ux_info "no state entries under $_repo_dir"
    fi
    ux_info ""
    ux_info "Run 'gh-pr-approve prune' to clean done entries and list failed worktrees."
}

# Scoped prune: only the PR numbers passed in are touched. Refuses to remove
# a state dir whose worker is still alive (unless --force) or whose worktree
# dir still exists (always rejected — that's `gwt teardown`'s job).
# $1 = repo state dir, $2 = force flag (0|1), $3 = repo name (header),
# remaining args = PR numbers.
_gh_pr_approve_prune_scoped() {
    local _repo_dir="$1" _force="$2" _name="$3"
    shift 3

    ux_header "gh-pr-approve prune - $_name"

    local _pr _entry _state _pid _wt _pid_alive
    local _processed=0 _rejected=0 _removed=0
    for _pr in "$@"; do
        _entry="$_repo_dir/$_pr"
        _processed=$((_processed + 1))
        if [ ! -d "$_entry" ]; then
            ux_warning "#$_pr no state to prune"
            continue
        fi
        _state="$(cat "$_entry/state" 2>/dev/null || printf '')"
        _pid="$(cat "$_entry/pid" 2>/dev/null || printf '')"
        _wt="$(cat "$_entry/worktree.path" 2>/dev/null || printf '')"

        _pid_alive=0
        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            _pid_alive=1
        fi

        # Worktree present? Always reject — even with --force. Tearing it down
        # is `gwt teardown`'s job (branch admin, secrets, git worktree prune).
        if [ -n "$_wt" ] && [ -d "$_wt" ]; then
            ux_error "#$_pr worktree exists at $_wt — run 'cd $_wt && gwt teardown --force' first"
            _rejected=$((_rejected + 1))
            continue
        fi

        # Alive worker? Accept only with --force.
        if [ "$_pid_alive" = "1" ]; then
            if [ "$_force" != "1" ]; then
                ux_error "#$_pr worker pid=$_pid still alive — pass --force to kill and remove"
                _rejected=$((_rejected + 1))
                continue
            fi
            ux_warning "#$_pr killing worker pid=$_pid"
            kill -TERM "$_pid" 2>/dev/null || true
            sleep 1
            if kill -0 "$_pid" 2>/dev/null; then
                kill -KILL "$_pid" 2>/dev/null || true
            fi
        fi

        rm -rf "$_entry"
        ux_success "removed state for #$_pr (was: ${_state:-unknown})"
        _removed=$((_removed + 1))
    done

    ux_info ""
    if [ "$_rejected" -gt 0 ]; then
        ux_warning "processed $_processed, removed $_removed, rejected $_rejected"
        return 1
    fi
    ux_success "processed $_processed, removed $_removed"
    return 0
}

# Prune state dirs. Two modes:
#   1) No positional args:  full-scan flow — remove 'done', list 'failed:*'
#      worktrees (and `gwt teardown` them when --force is set).
#   2) One or more PR numbers: scoped flow (see _gh_pr_approve_prune_scoped).
# Flag: --force changes scoped behavior (kill alive pid) and full-scan
# behavior (auto-teardown failed worktrees).
_gh_pr_approve_prune() {
    local _force=0
    local _scoped="" _arg _pr _parsing_flags=1

    while [ $# -gt 0 ]; do
        _arg="$1"
        if [ "$_parsing_flags" = "1" ]; then
            case "$_arg" in
            --force | -f)
                _force=1
                shift
                continue
                ;;
            --)
                _parsing_flags=0
                shift
                continue
                ;;
            -*)
                ux_error "gh-pr-approve prune: unknown arg '$_arg' (only --force is accepted)"
                return 1
                ;;
            esac
        fi

        _pr="${_arg#\#}"
        case "$_pr" in
        '' | *[!0-9]*)
            ux_error "gh-pr-approve prune: invalid PR number '$_arg'"
            return 1
            ;;
        esac
        _scoped="$_scoped $_pr"
        shift
    done

    local _root _name _repo_dir _entry _state _wt
    _root=$(_gh_pr_approve_state_root)
    _name=$(_gh_pr_approve_repo_name)
    if [ -z "$_name" ]; then
        ux_error "gh-pr-approve prune: not inside a git repo"
        return 1
    fi
    _repo_dir="$_root/$_name"

    if [ -n "$_scoped" ]; then
        # shellcheck disable=SC2086
        _gh_pr_approve_prune_scoped "$_repo_dir" "$_force" "$_name" $_scoped
        return $?
    fi

    ux_header "gh-pr-approve prune - $_name"
    if [ ! -d "$_repo_dir" ]; then
        ux_info "nothing to prune"
        return 0
    fi

    local _removed=0 _failed=0 _torn_down=0
    for _entry in "$_repo_dir"/*/; do
        [ -d "$_entry" ] || continue
        _pr="$(basename "$_entry")"
        _state="$(cat "$_entry/state" 2>/dev/null || printf '')"
        _wt="$(cat "$_entry/worktree.path" 2>/dev/null || printf '')"

        case "$_state" in
        done)
            rm -rf "$_entry"
            ux_success "removed state for #$_pr (done)"
            _removed=$((_removed + 1))
            ;;
        failed:*)
            _failed=$((_failed + 1))
            if [ "$_force" = "1" ] && [ -n "$_wt" ] && [ -d "$_wt" ]; then
                ux_warning "#$_pr $_state — tearing down $_wt"
                if (cd "$_wt" && gwt teardown --force); then
                    rm -rf "$_entry"
                    _torn_down=$((_torn_down + 1))
                else
                    ux_error "  gwt teardown failed for $_wt; leaving state dir intact"
                fi
            else
                ux_warning "#$_pr $_state"
                if [ -n "$_wt" ] && [ -d "$_wt" ]; then
                    ux_bullet_sub "worktree: $_wt"
                    ux_bullet_sub "cleanup: cd $_wt && gwt teardown --force"
                fi
            fi
            ;;
        esac
    done

    ux_info ""
    if [ "$_force" = "1" ]; then
        ux_success "pruned $_removed done entr(ies), torn down $_torn_down failed worktree(s); $((_failed - _torn_down)) failure(s) still need attention"
    else
        ux_success "pruned $_removed done entr(ies); $_failed failure(s) need attention (pass --force to gwt teardown them)"
    fi
}

# ============================================================================
# Help
# ============================================================================

gh_pr_approve_help() {
    ux_header "gh-pr-approve - fire-and-forget GitHub PR approval runner"
    ux_info "Usage:"
    ux_bullet "gh-pr-approve <pr-number>... [--ai <agent>] [--self-record|--admin-merge] [--squash|--rebase|--merge]"
    ux_bullet_sub "agent: claude (default) | codex | gemini"
    ux_bullet_sub "--self-record: for self-authored PRs, leave a comment-only review record"
    ux_bullet_sub "--admin-merge: for self-authored PRs, review then merge with gh pr merge --admin"
    ux_bullet_sub "--squash|--rebase|--merge: optional merge strategy for --admin-merge"
    ux_bullet "gh-pr-approve status [<N>]            full table, or per-PR diagnostic"
    ux_bullet "gh-pr-approve prune [--force] [<N>...] clean 'done' state, or scoped per-PR prune"
    ux_bullet "gh-pr-approve -h|--help|help"
    ux_info ""
    ux_info "Spawns one background worker per PR. Each worker:"
    ux_bullet "gwt spawn -> <ai> -p '/gh-pr-approve <N> [self-PR flags]' -> gwt teardown"
    ux_info ""
    ux_info "Examples:"
    ux_bullet "gh-pr-approve 42                            # single PR (default: claude)"
    ux_bullet "gh-pr-approve 12 34 56                      # 3 PRs in parallel"
    ux_bullet "gh-pr-approve 42 --ai codex                 # run worker with codex CLI"
    ux_bullet "gh-pr-approve --ai gemini '#56' '#78'       # gemini + #prefix"
    ux_bullet "gh-pr-approve 42 --self-record              # self-PR comment-only record"
    ux_bullet "gh-pr-approve 42 --admin-merge --squash     # self-PR admin merge"
    ux_bullet "gh-pr-approve status                        # full table — who's still running, who failed"
    ux_bullet "gh-pr-approve status 42                     # per-PR diagnostic (verdict + next action)"
    ux_bullet "gh-pr-approve prune                         # remove 'done' state dirs; print hints for failures"
    ux_bullet "gh-pr-approve prune --force                 # also gwt teardown failed worktrees"
    ux_bullet "gh-pr-approve prune 42 56                   # scoped — refuses if pid alive or worktree present"
    ux_bullet "gh-pr-approve prune --force 42              # scoped + kill alive pid (worktree still rejected)"
    ux_info ""
    ux_info "State directory: ~/.local/state/gh-pr-approve/<repo>/<pr>/"
    ux_bullet_sub "state         - current step"
    ux_bullet_sub "ai            - selected ai runner (claude|codex|gemini)"
    ux_bullet_sub "pid           - worker process id"
    ux_bullet_sub "worktree.path - git worktree path"
    ux_bullet_sub "flags         - launch flags (--self-record, --admin-merge, etc.)"
    ux_bullet_sub "log           - full stdout+stderr"
    ux_bullet_sub "log.prev      - previous run's log (one generation)"
    ux_bullet_sub "usage.jsonl   - per-invocation token usage (claude + codex + gemini)"
    ux_info ""
    ux_info "Failure isolation:"
    ux_bullet "One worker failure does not affect others."
    ux_bullet "Failed worker leaves worktree intact; state shows 'failed:<step>'."
    ux_bullet "Distinct failure states: failed:spawning, failed:approving, failed:tearing-down."
    ux_info ""
    ux_info "Preconditions:"
    ux_bullet "Run from main repo (not inside a worktree)"
    ux_bullet "gh CLI authenticated, selected AI CLI on PATH, gwt loaded"
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
    "" | -h | --help | help)
        gh_pr_approve_help
        return 0
        ;;
    status)
        shift
        _gh_pr_approve_status "$@"
        return $?
        ;;
    prune)
        shift
        _gh_pr_approve_prune "$@"
        return $?
        ;;
    esac

    # Parse optional args:
    #   --ai <claude|codex|gemini>
    #   --ai=<claude|codex|gemini>
    #   --self-record             (comment-only self-PR mode in skill)
    #   --admin-merge             (admin merge self-PR mode in skill)
    #   --squash|--rebase|--merge (optional admin merge strategy)
    # Position-agnostic: any flag may appear before, between, or after PR numbers.
    local _ai="claude"
    local _self_record=0
    local _admin_merge=0
    local _merge_strategy=""
    local _self_args=""
    local _pr_input=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --ai)
            shift
            if [ $# -eq 0 ]; then
                ux_error "missing value for --ai (expected: claude|codex|gemini)"
                return 1
            fi
            _ai="$1"
            ;;
        --ai=*)
            _ai="${1#--ai=}"
            ;;
        --self-ok)
            ux_error "--self-ok is not supported; GitHub blocks self-approval server-side"
            ux_info "Use --self-record for a comment-only audit trail or --admin-merge if you have admin rights."
            return 1
            ;;
        --self-record)
            _self_record=1
            ;;
        --admin-merge)
            _admin_merge=1
            ;;
        --squash | --rebase | --merge)
            if [ -n "$_merge_strategy" ]; then
                ux_error "multiple merge strategies provided: '$_merge_strategy' and '$1'"
                return 1
            fi
            _merge_strategy="$1"
            ;;
        -*)
            ux_error "unknown option: '$1'"
            ux_info "Usage: gh-pr-approve <pr-number>... [--ai <claude|codex|gemini>] [--self-record|--admin-merge]"
            return 1
            ;;
        *)
            _pr_input="$_pr_input $1"
            ;;
        esac
        shift
    done

    if [ "$_self_record" -eq 1 ] && [ "$_admin_merge" -eq 1 ]; then
        ux_error "--self-record and --admin-merge are mutually exclusive"
        return 1
    fi
    if [ -n "$_merge_strategy" ] && [ "$_admin_merge" -ne 1 ]; then
        ux_error "$_merge_strategy requires --admin-merge"
        return 1
    fi
    if [ "$_self_record" -eq 1 ]; then
        _self_args="--self-record"
    elif [ "$_admin_merge" -eq 1 ]; then
        _self_args="--admin-merge${_merge_strategy:+ $_merge_strategy}"
    fi

    if ! _gh_pr_approve_known_ai "$_ai"; then
        ux_error "invalid --ai value: '$_ai' (expected: claude|codex|gemini)"
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
    if ! _gh_pr_approve_require_ai_cli "$_ai"; then
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
    local _pr _pr_clean _pr_args="" _pr_count=0
    for _pr in $_pr_input; do
        _pr_clean="${_pr#\#}"
        case "$_pr_clean" in
        '' | *[!0-9]*)
            ux_error "invalid PR number: '$_pr' (must be positive integer, '#' prefix allowed)"
            return 1
            ;;
        esac
        _pr_args="$_pr_args $_pr_clean"
        _pr_count=$((_pr_count + 1))
    done

    if [ "$_pr_count" -eq 0 ]; then
        ux_error "no PR numbers provided"
        ux_info "Usage: gh-pr-approve <pr-number>... [--ai <claude|codex|gemini>] [--self-record|--admin-merge]"
        return 1
    fi

    ux_header "gh-pr-approve: spawning $_pr_count worker(s) (ai=$_ai${_self_args:+ flags=$_self_args})"
    for _pr in $_pr_args; do
        _gh_pr_approve_spawn_worker "$_pr" "$_ai" "$_self_args"
    done
    ux_success "All workers detached. Your shell is free. Results appear on the PR."
}

_gh_pr_approve_spawn_worker() {
    local _pr="$1"
    local _ai="${2:-claude}"
    local _self_args="${3:-}"
    local _dir _log _state _pid
    _dir=$(_gh_pr_approve_pr_dir "$_pr")
    mkdir -p "$_dir"
    _log="$_dir/log"
    printf '%s\n' "$_ai" >"$_dir/ai"
    # Record self-PR launch flags so `status <N>` can show them later.
    # Empty $_self_args → no file (status renders "(none)" then). Single
    # line, written even before the worker forks so a fail-fast spawn
    # still leaves a useful breadcrumb.
    if [ -n "$_self_args" ]; then
        printf '%s\n' "$_self_args" >"$_dir/flags"
    else
        rm -f "$_dir/flags" 2>/dev/null || true
    fi

    # Idempotency check — mirrors gh-flow semantics.
    _state=$(_gh_pr_approve_get_state "$_pr")
    case "$_state" in
    done)
        ux_info "#$_pr already done, skipping"
        return 0
        ;;
    spawning | approving | tearing-down)
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
        _gh_pr_approve_worker "$@"
    ' -- "$_pr" "$_ai" "$_self_args" </dev/null >"$_log" 2>&1 &
    _pid=$!
    disown "$_pid" 2>/dev/null || true
    printf '%s\n' "$_pid" >"$_dir/pid"
    ux_info "#$_pr -> pid=$_pid  ai=$_ai${_self_args:+ flags=$_self_args}  log=$_log"
}

# ============================================================================
# Worker (runs in a detached bash subshell)
# ============================================================================

_gh_pr_approve_worker() {
    local _pr="$1"
    local _ai="${2:-claude}"
    local _self_args="${3:-}"
    local _dir _worktree _spawn_name _usage_log _prompt
    _dir=$(_gh_pr_approve_pr_dir "$_pr")
    _spawn_name="pr-$_pr"
    # Resolve the usage log path while still in the main repo: once we cd
    # into the worktree, _gh_pr_approve_pr_dir would point elsewhere.
    _usage_log="$_dir/usage.jsonl"
    : >"$_usage_log"

    printf '[gh-pr-approve-worker] pr=#%s ai=%s%s start=%s\n' "$_pr" "$_ai" "${_self_args:+ flags=$_self_args}" "$(date -Iseconds 2>/dev/null || date)"

    # ---- Step 1: spawn worktree ----
    # Snapshot the worktree list before and after `gwt spawn` and diff them
    # to identify the new one. Same pattern as gh-flow — avoids coupling to
    # gwt's internal branch-naming convention.
    local _wt_before _wt_after
    _gh_pr_approve_set_state "$_dir" "spawning"
    _wt_before=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    if ! gwt spawn "$_spawn_name"; then
        _gh_pr_approve_set_state "$_dir" "failed:spawning"
        printf '[gh-pr-approve-worker] gwt spawn failed\n' >&2
        return 1
    fi

    _wt_after=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    _worktree=$(comm -13 \
        <(printf '%s\n' "$_wt_before" | sort) \
        <(printf '%s\n' "$_wt_after" | sort) |
        head -n 1)

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

    # ---- Step 2: approve (selected ai runs /gh-pr-approve <N>) ----
    # Single-shot. The skill either approves with LGTM or files follow-up
    # issues and exits. No polling, no reply loop — that's gh-flow's job.
    # Append selected self-PR mode flags so the skill can avoid GitHub's
    # server-side self-approval block.
    _gh_pr_approve_set_state "$_dir" "approving"
    _prompt="/gh-pr-approve $_pr${_self_args:+ $_self_args}"
    if ! _gh_pr_approve_run_ai_prompt "$_ai" "$_usage_log" "$_prompt" "$_prompt"; then
        _gh_pr_approve_set_state "$_dir" "failed:approving"
        printf '[gh-pr-approve-worker] /gh-pr-approve failed\n' >&2
        # Print usage even on failure — knowing how much quota a failed
        # call consumed is half the reason this tracking exists.
        _ai_usage_summary "$_usage_log" "Token Usage (PR #$_pr — failed)"
        return 1
    fi

    # ---- Step 3: teardown (must run inside the worktree) ----
    # The skill is read-only (no file edits); worktree has nothing to push
    # and can be torn down immediately after the review is submitted.
    _gh_pr_approve_set_state "$_dir" "tearing-down"
    if ! gwt teardown --force; then
        _gh_pr_approve_set_state "$_dir" "failed:tearing-down"
        printf '[gh-pr-approve-worker] gwt teardown failed\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (PR #$_pr — teardown failed)"
        return 1
    fi

    _gh_pr_approve_set_state "$_dir" "done"
    printf '[gh-pr-approve-worker] done pr=#%s end=%s\n' "$_pr" "$(date -Iseconds 2>/dev/null || date)"
    _ai_usage_summary "$_usage_log" "Token Usage (PR #$_pr)"
}

# ============================================================================
# Aliases (hyphenated command names per shell-common convention)
# ============================================================================

alias gh-pr-approve='gh_pr_approve'
alias gh-pr-approve-help='gh_pr_approve_help'
