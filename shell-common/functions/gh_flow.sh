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
# Post-condition helpers (worker uses these to verify each step did real work)
# ============================================================================

# Returns 0 if the current tree has something /gh-commit could commit:
# staged, unstaged, or untracked changes. (Runs inside the worktree.)
_gh_flow_has_work_for_commit() {
    [ -n "$(git status --porcelain 2>/dev/null | head -n1)" ]
}

# Returns 0 if the current branch has at least one commit ahead of
# the upstream default branch (origin/HEAD). Used to verify /gh-commit.
_gh_flow_has_branch_commits() {
    local _base _count
    _base="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/||')"
    if [ -z "$_base" ]; then
        _base="origin/main"
    fi
    _count="$(git rev-list --count "HEAD" "^$_base" 2>/dev/null || echo 0)"
    [ "${_count:-0}" -gt 0 ]
}

# Returns 0 if the ai runner is one of: claude, codex, gemini.
_gh_flow_known_ai() {
    case "$1" in
    claude | codex | gemini) return 0 ;;
    *) return 1 ;;
    esac
}

# Ensure the selected ai CLI exists in PATH.
_gh_flow_require_ai_cli() {
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
# Delegates to ai_usage.sh so each invocation appends a usage record
# (tokens, cost, duration) to <state-dir>/usage.jsonl. A gh-flow worker
# typically issues 4–6 ai calls per issue (implement, commit, pr, reply
# on demand, merge); the tail-end _ai_usage_summary aggregates them so
# the user sees the per-issue total — which was the missing signal
# behind the "10-minute MAX quota burn" incident.
_gh_flow_run_ai_prompt() {
    local _ai="$1" _usage_log="$2" _label="$3" _prompt="$4"
    _ai_usage_run "$_ai" "$_usage_log" "$_label" "$_prompt"
}

# ============================================================================
# Verdict helpers (shared between status and scoped prune)
# ============================================================================

# Echo one of: MERGED | CLOSED | OPEN | EMPTY | UNREACHABLE
# - EMPTY: pr.number missing or empty (worker never opened a PR)
# - UNREACHABLE: gh CLI failed (network/auth) — verdict layer must tolerate it
_gh_flow_pr_state() {
    local _dir="$1"
    local _pr_num _state _rc
    if [ ! -s "$_dir/pr.number" ]; then
        printf 'EMPTY'
        return 0
    fi
    _pr_num="$(cat "$_dir/pr.number" 2>/dev/null)"
    if [ -z "$_pr_num" ]; then
        printf 'EMPTY'
        return 0
    fi
    _state="$(gh pr view "$_pr_num" --json state --jq '.state? // empty' 2>/dev/null)"
    _rc=$?
    if [ "$_rc" -ne 0 ] || [ -z "$_state" ]; then
        printf 'UNREACHABLE'
        return 0
    fi
    printf '%s' "$_state"
}

# Print two lines for the given issue:
#   <verdict-text>
#   <next-action-text>
# Reads <issue-dir>/state, /pid, /worktree.path, /pr.number, then composes the
# matrix from the issue spec. Used by `gh-flow status <N>`; `gh-flow prune <N>`
# can reuse the same source-of-truth in future iterations.
_gh_flow_verdict() {
    local _issue="$1"
    local _dir _state _wt _pid _pid_alive _pr_state _verdict _action
    _dir=$(_gh_flow_issue_dir "$_issue")
    if [ ! -d "$_dir" ]; then
        printf 'no state — issue not tracked\n(none)\n'
        return 0
    fi
    _state="$(cat "$_dir/state" 2>/dev/null || printf 'unknown')"
    _wt="$(cat "$_dir/worktree.path" 2>/dev/null || printf '')"
    _pid="$(cat "$_dir/pid" 2>/dev/null || printf '')"
    _pid_alive=0
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        _pid_alive=1
    fi
    _pr_state=$(_gh_flow_pr_state "$_dir")

    case "$_state" in
    done)
        _verdict="done — safe to prune"
        _action="gh-flow prune $_issue"
        ;;
    polling)
        case "$_pr_state" in
        MERGED | CLOSED)
            _verdict="stuck poller — PR resolved, worker missed it"
            if [ "$_pid_alive" = "1" ]; then
                _action="gh-flow prune --force $_issue"
            else
                _action="gh-flow prune $_issue"
            fi
            ;;
        OPEN)
            _verdict="active polling — leave alone"
            _action="(none — still working)"
            ;;
        *)
            _verdict="stuck pre-PR — investigate log ($_pr_state)"
            if [ "$_pid_alive" = "1" ]; then
                _action="review 'tail -40 $_dir/log', then gh-flow prune --force $_issue"
            else
                _action="review 'tail -40 $_dir/log', then gh-flow prune $_issue"
            fi
            ;;
        esac
        ;;
    failed:*)
        if [ -n "$_wt" ] && [ -d "$_wt" ]; then
            _verdict="dead failure, worktree alive"
            _action="cd $_wt && gwt teardown --force, then gh-flow prune $_issue"
        else
            _verdict="dead failure — state-only cleanup"
            _action="gh-flow prune $_issue"
        fi
        ;;
    spawning | implementing | committing | opening-pr | replying | merging | tearing-down)
        if [ "$_pid_alive" = "1" ]; then
            _verdict="active worker ($_state) — leave alone"
            _action="(none — still working)"
        else
            _verdict="dead worker mid-step ($_state)"
            _action="gh-flow prune $_issue"
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

# Per-issue diagnostic. Renders the layout from issue #252:
#   header + State/Worker/PR/Worktree/Markers/Last log (+ tail -5)
#   + Verdict / Next action (via _gh_flow_verdict).
# Input: <issue-num> with optional leading '#'.
_gh_flow_status_single() {
    local _arg="$1"
    local _issue _dir _state _pid _wt _pr_num _pid_state _wt_state
    local _pr_state _pr_date _pr_info _markers _log _log_mtime _etime
    local _verdict_out _verdict_text _action_text _name

    _issue="${_arg#\#}"
    case "$_issue" in
    '' | *[!0-9]*)
        ux_error "gh-flow status: invalid issue number '$_arg'"
        return 1
        ;;
    esac

    _name=$(_gh_flow_repo_name)
    if [ -z "$_name" ]; then
        ux_error "gh-flow status: not inside a git repo"
        return 1
    fi

    _dir=$(_gh_flow_issue_dir "$_issue")
    ux_header "gh-flow status #$_issue - $_name"
    if [ ! -d "$_dir" ]; then
        ux_warning "no state for #$_issue in $_name (worker never ran or already pruned)"
        return 0
    fi

    _state="$(cat "$_dir/state" 2>/dev/null || printf 'unknown')"
    _pid="$(cat "$_dir/pid" 2>/dev/null || printf '')"
    _wt="$(cat "$_dir/worktree.path" 2>/dev/null || printf '')"
    _pr_num="$(cat "$_dir/pr.number" 2>/dev/null || printf '')"

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

    # PR detail: state from _gh_flow_pr_state, plus a date for MERGED/CLOSED.
    if [ -n "$_pr_num" ]; then
        _pr_state=$(_gh_flow_pr_state "$_dir")
        case "$_pr_state" in
        MERGED)
            _pr_date="$(gh pr view "$_pr_num" --json mergedAt --jq '.mergedAt? | select(. != null) | split("T")[0]' 2>/dev/null)"
            _pr_info="#$_pr_num (MERGED${_pr_date:+, $_pr_date})"
            ;;
        CLOSED)
            _pr_date="$(gh pr view "$_pr_num" --json closedAt --jq '.closedAt? | select(. != null) | split("T")[0]' 2>/dev/null)"
            _pr_info="#$_pr_num (CLOSED${_pr_date:+, $_pr_date})"
            ;;
        OPEN) _pr_info="#$_pr_num (OPEN)" ;;
        UNREACHABLE) _pr_info="#$_pr_num (unreachable — gh CLI failed)" ;;
        *) _pr_info="#$_pr_num ($_pr_state)" ;;
        esac
    else
        _pr_info="(none — worker never opened one)"
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

    # Markers we know about today.
    _markers=""
    [ -f "$_dir/reply.done" ] && _markers="${_markers}reply.done "
    _markers="${_markers% }"
    [ -z "$_markers" ] && _markers="(none)"

    ux_table_row "State" "$_state"
    ux_table_row "Worker" "$_pid_state"
    ux_table_row "PR" "$_pr_info"
    ux_table_row "Worktree" "$_wt_state"
    ux_table_row "Markers" "$_markers"

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
    _verdict_out=$(_gh_flow_verdict "$_issue")
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

# List all known gh-flow entries for the current repo, OR diagnose a single
# issue if exactly one positional arg is given. Multiple positional args are
# rejected (single-issue diagnostic only).
# Output (no-arg): a table of issue / state / pid-liveness / worktree path.
# Output (1 arg):  see _gh_flow_status_single.
_gh_flow_status() {
    if [ $# -gt 1 ]; then
        ux_error "gh-flow status: only one issue number accepted (got $#)"
        return 1
    fi
    if [ -n "${1:-}" ]; then
        _gh_flow_status_single "$1"
        return $?
    fi

    local _root _name _repo_dir _entry _issue _state _pid _wt _pid_state
    _root=$(_gh_flow_state_root)
    _name=$(_gh_flow_repo_name)
    if [ -z "$_name" ]; then
        ux_error "gh-flow status: not inside a git repo"
        return 1
    fi
    _repo_dir="$_root/$_name"

    ux_header "gh-flow status - $_name"
    if [ ! -d "$_repo_dir" ]; then
        ux_info "no state — no workers have ever run in this repo"
        return 0
    fi

    local _found=0
    ux_table_header "ISSUE" "STATE" "PID / WORKTREE"
    for _entry in "$_repo_dir"/*/; do
        [ -d "$_entry" ] || continue
        _issue="$(basename "$_entry")"
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
            ux_table_row "#$_issue" "$_state" "$_pid_state  $_wt"
        else
            ux_table_row "#$_issue" "$_state" "$_pid_state"
        fi
        _found=1
    done
    if [ "$_found" = "0" ]; then
        ux_info "no state entries under $_repo_dir"
    fi
    ux_info ""
    ux_info "Run 'gh-flow prune' to clean done entries and list failed worktrees."
}

# Scoped prune: only the issue numbers passed in are touched. Refuses to
# remove a state dir whose worker is still alive (unless --force) or whose
# worktree dir still exists (always rejected — that's `gwt teardown`'s job).
# $1 = repo state dir, $2 = force flag (0|1), $3 = repo name (for header),
# remaining args = issue numbers.
_gh_flow_prune_scoped() {
    local _repo_dir="$1" _force="$2" _name="$3"
    shift 3

    ux_header "gh-flow prune - $_name"

    local _issue _entry _state _pid _wt _pid_alive
    local _processed=0 _rejected=0 _removed=0
    for _issue in "$@"; do
        _entry="$_repo_dir/$_issue"
        _processed=$((_processed + 1))
        if [ ! -d "$_entry" ]; then
            ux_warning "#$_issue no state to prune"
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
            ux_error "#$_issue worktree exists at $_wt — run 'cd $_wt && gwt teardown --force' first"
            _rejected=$((_rejected + 1))
            continue
        fi

        # Alive worker? Accept only with --force.
        if [ "$_pid_alive" = "1" ]; then
            if [ "$_force" != "1" ]; then
                ux_error "#$_issue worker pid=$_pid still alive — pass --force to kill and remove"
                _rejected=$((_rejected + 1))
                continue
            fi
            ux_warning "#$_issue killing worker pid=$_pid"
            kill -TERM "$_pid" 2>/dev/null || true
            sleep 1
            if kill -0 "$_pid" 2>/dev/null; then
                kill -KILL "$_pid" 2>/dev/null || true
            fi
        fi

        rm -rf "$_entry"
        ux_success "removed state for #$_issue (was: ${_state:-unknown})"
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
#   2) One or more issue numbers: scoped flow (see _gh_flow_prune_scoped).
# Flag: --force changes scoped behavior (kill alive pid) and full-scan
# behavior (auto-teardown failed worktrees).
_gh_flow_prune() {
    local _force=0
    local _scoped="" _arg _issue

    while [ $# -gt 0 ]; do
        case "$1" in
        --force | -f) _force=1 ;;
        --)
            shift
            break
            ;;
        -*)
            ux_error "gh-flow prune: unknown arg '$1' (only --force is accepted)"
            return 1
            ;;
        *)
            _arg="$1"
            _issue="${_arg#\#}"
            case "$_issue" in
            '' | *[!0-9]*)
                ux_error "gh-flow prune: invalid issue number '$_arg'"
                return 1
                ;;
            esac
            _scoped="$_scoped $_issue"
            ;;
        esac
        shift
    done
    # After --, any remaining args are positional issue numbers.
    while [ $# -gt 0 ]; do
        _arg="$1"
        _issue="${_arg#\#}"
        case "$_issue" in
        '' | *[!0-9]*)
            ux_error "gh-flow prune: invalid issue number '$_arg'"
            return 1
            ;;
        esac
        _scoped="$_scoped $_issue"
        shift
    done

    local _root _name _repo_dir _entry _state _wt
    _root=$(_gh_flow_state_root)
    _name=$(_gh_flow_repo_name)
    if [ -z "$_name" ]; then
        ux_error "gh-flow prune: not inside a git repo"
        return 1
    fi
    _repo_dir="$_root/$_name"

    if [ -n "$_scoped" ]; then
        # shellcheck disable=SC2086
        _gh_flow_prune_scoped "$_repo_dir" "$_force" "$_name" $_scoped
        return $?
    fi

    ux_header "gh-flow prune - $_name"
    if [ ! -d "$_repo_dir" ]; then
        ux_info "nothing to prune"
        return 0
    fi

    local _removed=0 _failed=0 _torn_down=0
    for _entry in "$_repo_dir"/*/; do
        [ -d "$_entry" ] || continue
        _issue="$(basename "$_entry")"
        _state="$(cat "$_entry/state" 2>/dev/null || printf '')"
        _wt="$(cat "$_entry/worktree.path" 2>/dev/null || printf '')"

        case "$_state" in
        done)
            rm -rf "$_entry"
            ux_success "removed state for #$_issue (done)"
            _removed=$((_removed + 1))
            ;;
        failed:*)
            _failed=$((_failed + 1))
            if [ "$_force" = "1" ] && [ -n "$_wt" ] && [ -d "$_wt" ]; then
                ux_warning "#$_issue $_state — tearing down $_wt"
                if (cd "$_wt" && gwt teardown --force); then
                    rm -rf "$_entry"
                    _torn_down=$((_torn_down + 1))
                else
                    ux_error "  gwt teardown failed for $_wt; leaving state dir intact"
                fi
            else
                ux_warning "#$_issue $_state"
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

gh_flow_help() {
    ux_header "gh-flow - fire-and-forget GitHub issue → PR automation"
    ux_info "Usage:"
    ux_bullet "gh-flow <issue-number>... [--ai <agent>]  spawn N parallel workers"
    ux_bullet_sub "agent: claude (default) | codex | gemini"
    ux_bullet "gh-flow status [<N>]            full table, or per-issue diagnostic"
    ux_bullet "gh-flow prune [--force] [<N>...] clean 'done' state, or scoped per-issue prune"
    ux_bullet "gh-flow -h|--help|help           this help"
    ux_info ""
    ux_info "Spawn pipeline (each worker runs these sequentially):"
    ux_bullet "gwt spawn → /gh-issue-implement → /gh-commit → /gh-pr"
    ux_bullet "poll reviews → /gh-pr-reply (once, if comments)"
    ux_bullet "poll for APPROVED → /gh-pr-merge → gwt teardown"
    ux_info ""
    ux_info "Examples:"
    ux_bullet "gh-flow 13                  # single issue"
    ux_bullet "gh-flow 13 42 88            # 3 issues in parallel"
    ux_bullet "gh-flow 33 --ai codex       # run workers with codex CLI"
    ux_bullet "gh-flow --ai gemini 44      # run workers with gemini CLI"
    ux_bullet "gh-flow status              # full table — who's still running, who failed"
    ux_bullet "gh-flow status 153          # per-issue diagnostic (verdict + next action)"
    ux_bullet "gh-flow prune               # remove 'done' state dirs; print hints for failures"
    ux_bullet "gh-flow prune --force       # also gwt teardown failed worktrees"
    ux_bullet "gh-flow prune 153 199       # scoped — refuses if pid alive or worktree present"
    ux_bullet "gh-flow prune --force 153   # scoped + kill alive pid (worktree still rejected)"
    ux_info ""
    ux_info "State directory: ~/.local/state/gh-flow/<repo>/<issue>/"
    ux_bullet_sub "state         - current step"
    ux_bullet_sub "pid           - worker process id"
    ux_bullet_sub "worktree.path - git worktree path"
    ux_bullet_sub "pr.number     - PR number"
    ux_bullet_sub "reply.done    - marker (present if reply already ran)"
    ux_bullet_sub "log           - full stdout+stderr"
    ux_bullet_sub "usage.jsonl   - per-invocation token usage (claude + codex + gemini)"
    ux_info ""
    ux_info "Failure isolation:"
    ux_bullet "One worker failure does not affect others."
    ux_bullet "Failed worker leaves worktree intact; state shows 'failed:<step>'."
    ux_bullet "Distinct failure states: failed:implementing, failed:committing,"
    ux_bullet_sub "failed:opening-pr, failed:replying, failed:merging, failed:tearing-down."
    ux_info ""
    ux_info "Preconditions:"
    ux_bullet "Run from main repo (not inside a worktree)"
    ux_bullet "gh CLI authenticated, selected AI CLI on PATH, gwt loaded"
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
    "" | -h | --help | help)
        gh_flow_help
        return 0
        ;;
    status)
        shift
        _gh_flow_status "$@"
        return $?
        ;;
    prune)
        shift
        _gh_flow_prune "$@"
        return $?
        ;;
    esac

    # Parse optional args:
    #   --ai <claude|codex|gemini>
    #   --ai=<claude|codex|gemini>
    local _ai="claude"
    local _issue_args=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --ai)
            shift
            if [ $# -eq 0 ]; then
                ux_error "--ai requires a value (claude|codex|gemini)"
                return 1
            fi
            _ai="$1"
            ;;
        --ai=*)
            _ai="${1#--ai=}"
            ;;
        -*)
            ux_error "unknown option: '$1'"
            ux_info "Usage: gh-flow <issue-number>... [--ai <claude|codex|gemini>]"
            return 1
            ;;
        *)
            _issue_args="$_issue_args $1"
            ;;
        esac
        shift
    done

    # Restore issue args for numeric validation / spawn loop.
    # shellcheck disable=SC2086
    set -- $_issue_args
    if [ $# -eq 0 ]; then
        ux_error "no issue numbers provided"
        ux_info "Usage: gh-flow <issue-number>... [--ai <claude|codex|gemini>]"
        return 1
    fi

    if ! _gh_flow_known_ai "$_ai"; then
        ux_error "invalid --ai value: '$_ai' (allowed: claude, codex, gemini)"
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
    if ! _gh_flow_require_ai_cli "$_ai"; then
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
        '' | *[!0-9]*)
            ux_error "invalid issue number: '$_issue' (must be positive integer)"
            ux_info "subcommands: status, prune; or pass one or more issue numbers"
            return 1
            ;;
        esac
    done

    ux_header "gh-flow: spawning $# worker(s) (ai=$_ai)"
    for _issue in "$@"; do
        _gh_flow_spawn_worker "$_issue" "$_ai"
    done
    ux_success "All workers detached. Your shell is free. Results will appear on the kanban."
}

_gh_flow_spawn_worker() {
    local _issue="$1"
    local _ai="${2:-claude}"
    local _dir _log _state _pid
    _dir=$(_gh_flow_issue_dir "$_issue")
    mkdir -p "$_dir"
    _log="$_dir/log"
    printf '%s\n' "$_ai" >"$_dir/ai"

    # Idempotency check
    _state=$(_gh_flow_get_state "$_issue")
    case "$_state" in
    done)
        ux_info "#$_issue already done, skipping"
        return 0
        ;;
    spawning | implementing | committing | opening-pr | polling | replying | merging | tearing-down)
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
        _gh_flow_worker "$1" "$2"
    ' -- "$_issue" "$_ai" </dev/null >"$_log" 2>&1 &
    _pid=$!
    disown "$_pid" 2>/dev/null || true
    printf '%s\n' "$_pid" >"$_dir/pid"
    ux_info "#$_issue → pid=$_pid  ai=$_ai  log=$_log"
}

# ============================================================================
# Worker (runs in a detached bash subshell)
# ============================================================================

_gh_flow_worker() {
    local _issue="$1"
    local _ai="${2:-claude}"
    local _dir _worktree _pr _spawn_name _decision _comments _usage_log
    _dir=$(_gh_flow_issue_dir "$_issue")
    _spawn_name="issue-$_issue"
    # Resolve the usage log path while still in the main repo: once we cd
    # into the worktree, _gh_flow_issue_dir would point elsewhere.
    _usage_log="$_dir/usage.jsonl"
    : >"$_usage_log"

    printf '[gh-flow-worker] issue=#%s ai=%s start=%s\n' "$_issue" "$_ai" "$(date -Iseconds 2>/dev/null || date)"

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
        <(printf '%s\n' "$_wt_after" | sort) |
        head -n 1)

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

    # ---- Step 2a: implement (selected ai runs /gh-issue-implement) ----
    # The original single `/gh-issue-flow` call was unreliable in
    # non-interactive mode: it often stopped after the implement phase and printed
    # a "Next: …" hint without running commit/PR. We invoke the 3 atomic skills
    # ourselves so each phase has a distinct state + post-condition check.
    _gh_flow_set_state "$_dir" "implementing"
    _gh_project_status_sync issue "$_issue" "In progress"
    if ! _gh_flow_run_ai_prompt "$_ai" "$_usage_log" "/gh-issue-implement $_issue direct" "/gh-issue-implement $_issue direct"; then
        _gh_flow_set_state "$_dir" "failed:implementing"
        printf '[gh-flow-worker] /gh-issue-implement failed\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue — failed: implementing)"
        return 1
    fi
    if ! _gh_flow_has_work_for_commit; then
        _gh_flow_set_state "$_dir" "failed:implementing"
        printf '[gh-flow-worker] /gh-issue-implement produced no changes\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue — failed: implementing/no-op)"
        return 1
    fi

    # ---- Step 2b: commit (selected ai runs /gh-commit) ----
    _gh_flow_set_state "$_dir" "committing"
    if ! _gh_flow_run_ai_prompt "$_ai" "$_usage_log" "/gh-commit" "/gh-commit"; then
        _gh_flow_set_state "$_dir" "failed:committing"
        printf '[gh-flow-worker] /gh-commit failed\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue — failed: committing)"
        return 1
    fi
    if ! _gh_flow_has_branch_commits; then
        _gh_flow_set_state "$_dir" "failed:committing"
        printf '[gh-flow-worker] /gh-commit left no new commit on branch\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue — failed: committing/no-commit)"
        return 1
    fi

    # ---- Step 2c: open PR (selected ai runs /gh-pr) ----
    _gh_flow_set_state "$_dir" "opening-pr"
    if ! _gh_flow_run_ai_prompt "$_ai" "$_usage_log" "/gh-pr $_issue" "/gh-pr $_issue"; then
        _gh_flow_set_state "$_dir" "failed:opening-pr"
        printf '[gh-flow-worker] /gh-pr failed\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue — failed: opening-pr)"
        return 1
    fi
    _pr="$(gh pr view --json number --jq '.number' 2>/dev/null)"
    if [ -z "$_pr" ]; then
        _gh_flow_set_state "$_dir" "failed:opening-pr"
        printf '[gh-flow-worker] /gh-pr did not create a PR\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue — failed: opening-pr/no-pr)"
        return 1
    fi
    printf '%s\n' "$_pr" >"$_dir/pr.number"
    printf '[gh-flow-worker] PR=#%s\n' "$_pr"
    # PR card auto-transition is not covered by any built-in workflow;
    # move it to "In review" explicitly so reviewers see it on the board.
    _gh_project_status_sync pr "$_pr" "In review"

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
                if _gh_flow_run_ai_prompt "$_ai" "$_usage_log" "/gh-pr-reply" "/gh-pr-reply"; then
                    touch "$_dir/reply.done"
                    _gh_flow_set_state "$_dir" "polling"
                else
                    _gh_flow_set_state "$_dir" "failed:replying"
                    printf '[gh-flow-worker] /gh-pr-reply failed\n' >&2
                    _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue — failed: replying)"
                    return 1
                fi
            fi
        fi
    done

    # ---- Step 4: merge ----
    _gh_flow_set_state "$_dir" "merging"
    if ! _gh_flow_run_ai_prompt "$_ai" "$_usage_log" "/gh-pr-merge" "/gh-pr-merge"; then
        _gh_flow_set_state "$_dir" "failed:merging"
        printf '[gh-flow-worker] /gh-pr-merge failed\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue — failed: merging)"
        return 1
    fi

    # ---- Step 5: teardown (must run inside the worktree) ----
    _gh_flow_set_state "$_dir" "tearing-down"
    if ! gwt teardown --force; then
        _gh_flow_set_state "$_dir" "failed:tearing-down"
        printf '[gh-flow-worker] gwt teardown failed\n' >&2
        _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue — failed: tearing-down)"
        return 1
    fi

    _gh_flow_set_state "$_dir" "done"
    printf '[gh-flow-worker] done issue=#%s end=%s\n' "$_issue" "$(date -Iseconds 2>/dev/null || date)"
    _ai_usage_summary "$_usage_log" "Token Usage (issue #$_issue)"
}

# ============================================================================
# Project board Status sync
# ============================================================================
# Helper extracted to shell-common/functions/gh_project_status.sh so /gh-pr
# and /gh-commit (single-skill execution paths, not the gh-flow worker) can
# also push board transitions. The worker calls _gh_project_status_sync at
# Step 2a (implement → "In progress") and after Step 2c (PR opened →
# "In review"); see lines 412 and 454.

# ============================================================================
# Aliases (hyphenated command names per shell-common convention)
# ============================================================================

alias gh-flow='gh_flow'
alias gh-flow-help='gh_flow_help'
