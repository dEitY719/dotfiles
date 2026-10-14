#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/git_worktree.sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Git worktree management functions (split from git.sh): the gwt dispatcher,
# list/status/add/remove/prune, and helpers shared with spawn/teardown.
# Split (#2156): gwt-help -> gwt_help.sh, spawn/teardown ->
# git_worktree_spawn.sh, AI launch -> shell-common/lib/agent_launch.sh.

# Override Oh My Zsh's gwt alias (zsh only)
unalias gwt 2>/dev/null || true

# ============================================================================
# gwt — git worktree dispatcher
# Usage: gwt <subcommand> [args...]
# ============================================================================
gwt() {
    case "${1:-}" in
        add)       shift; git_worktree_add "$@" ;;
        list|ls)   shift; git_worktree_list "$@" ;;
        remove|rm) shift; git_worktree_remove "$@" ;;
        prune)     shift; git_worktree_prune "$@" ;;
        spawn)     shift; git_worktree_spawn "$@" ;;
        status)    shift; git_worktree_status "$@" ;;
        teardown)  shift; git_worktree_teardown "$@" ;;
        help)
            ux_error "Use canonical entrypoint: gwt-help (not 'gwt help')"
            ux_info "Try: gwt-help"
            return 1
            ;;
        -h|--help|"")
            [ $# -gt 0 ] && shift
            gwt_help "$@"
            ;;
        *)
            ux_error "Unknown command: $1"
            ux_info "Run: gwt-help"
            return 1
            ;;
    esac
}

# ============================================================================
# Internal: read a worktree's gitdir pointer (.git file). Echoes the bare
# path on stdout if the file exists and contains a `gitdir:` line; returns 1
# otherwise. Centralized so callers don't re-invent the parser per PR #284
# review feedback.
# ============================================================================
_gwt_read_gitdir_pointer() {
    [ -f "$1" ] || return 1
    sed -n 's/^gitdir:[[:space:]]*//p' "$1"
}

# ============================================================================
# Internal: detect an orphaned worktree (parent repo deleted out from under it).
# Returns 0 and echoes the broken admin-dir path when $PWD/.git is a regular
# file whose `gitdir:` pointer leads to a missing directory. Returns 1 on a
# healthy worktree, a main repo (.git is a directory), or a non-git pwd.
# ============================================================================
_gwt_diagnose_orphan() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local pointer
    pointer=$(_gwt_read_gitdir_pointer .git) || return 1
    [ -n "$pointer" ] || return 1
    [ -d "$pointer" ] && return 1
    printf '%s\n' "$pointer"
}

# ============================================================================
# Internal: emit the right "no git here" diagnostic. Bare error for a true
# non-git pwd; actionable recovery for an orphaned worktree (.git pointer
# leads to a deleted admin dir — issue #282). Always returns 1 so callers can
# `_gwt_report_no_git; return 1` to propagate.
# ============================================================================
_gwt_report_no_git() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local broken
    if broken=$(_gwt_diagnose_orphan); then
        ux_error "Worktree's parent repo is gone — .git points to: $broken"
        ux_info "  This worktree was created from a repo that has since been deleted."
        ux_info "  Recover from outside this directory:"
        ux_bullet "rm -rf \"$(pwd)\""
        ux_bullet "Then in any other repo that registered this worktree: gwt prune"
    else
        ux_error "Not inside a git repository"
    fi
    return 1
}

# ============================================================================
# Status helpers (issue #285) — verdict matrix + per-worktree signals.
# Mirrors the gh-flow status pattern (`gh_flow.sh:152-223`) so users get
# consistent "what is this thing doing now / what should I do next" output
# across both subsystems. Local signals only by default; --remote mode
# layers in PR state via a single batched gh CLI call.
# ============================================================================

# Echo a short, human-readable age (e.g., "5m", "2h", "5d", "3w") for the
# HEAD commit at <wt_path>. Echo "-" if path missing or no commits yet.
# Args: <wt_path>
_gwt_age() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _diff
    # Delegate timestamp+now+diff to _gwt_age_seconds — keeps a single
    # source of truth for "how do we measure commit age" (PR #286 review).
    _diff=$(_gwt_age_seconds "$1" 2>/dev/null) || {
        printf '%s' "-"
        return 0
    }
    if [ "$_diff" -lt 3600 ]; then
        printf '%dm' "$((_diff / 60))"
    elif [ "$_diff" -lt 86400 ]; then
        printf '%dh' "$((_diff / 3600))"
    elif [ "$_diff" -lt 604800 ]; then
        printf '%dd' "$((_diff / 86400))"
    else
        printf '%dw' "$((_diff / 604800))"
    fi
}

# Echo seconds since HEAD's commit time, or empty if unavailable.
# Args: <wt_path>
_gwt_age_seconds() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _wt="$1" _ts _now
    [ -d "$_wt" ] || return 1
    _ts="$(git -C "$_wt" log -1 --format=%ct HEAD 2>/dev/null)"
    [ -n "$_ts" ] || return 1
    _now="$(date +%s)"
    printf '%d' "$((_now - _ts))"
}

# Return 0 if worktree has uncommitted, staged, or untracked changes.
# `git status --porcelain` covers all three in one fork — cheaper than
# the three-call pattern in _gwt_teardown_one_inplace.
# Args: <wt_path>
_gwt_signal_dirty() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _wt="$1" _porcelain
    [ -d "$_wt" ] || return 1
    _porcelain="$(git -C "$_wt" status --porcelain 2>/dev/null)"
    [ -n "$_porcelain" ]
}

# Echo the picked main ref ("origin/main", "origin/master", "main", "master")
# from the perspective of the current repo. Empty if no candidate exists.
_gwt_main_ref() {
    if git rev-parse --verify --quiet "origin/main" >/dev/null 2>&1; then
        printf 'origin/main'
    elif git rev-parse --verify --quiet "origin/master" >/dev/null 2>&1; then
        printf 'origin/master'
    elif git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
        printf 'main'
    elif git rev-parse --verify --quiet "master" >/dev/null 2>&1; then
        printf 'master'
    fi
}

# Echo number of commits on <branch> not in <main_ref>. Empty on failure.
# Args: <branch> <main_ref>
_gwt_signal_ahead() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _branch="$1" _main_ref="$2"
    [ -n "$_branch" ] && [ -n "$_main_ref" ] || return 1
    git rev-list --count "$_main_ref..$_branch" 2>/dev/null
}

# Batch-fetch open/closed/merged PR states for the current repo. Echoes one
# line per PR: "<branch> <state>". Caller looks up by branch name. Single
# network call regardless of worktree count — see issue #285 §D.
_gwt_remote_pr_states() {
    command -v gh >/dev/null 2>&1 || return 1
    gh pr list --state all --limit 50 \
        --json headRefName,number,state \
        --jq '.[] | "\(.headRefName) \(.state) \(.number)"' 2>/dev/null
}

# Look up <branch> in the PR-state table emitted by _gwt_remote_pr_states.
# Echoes "<state> <num>" on hit, empty on miss. Newest match wins (gh pr
# list returns newest first, so the first hit is the freshest PR).
# Args: <branch> <pr_states_text>
_gwt_pr_lookup() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _branch="$1" _states="$2" _line _head _state _num
    [ -n "$_branch" ] && [ -n "$_states" ] || return 1
    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _head="${_line%% *}"
        if [ "$_head" = "$_branch" ]; then
            _line="${_line#* }"
            _state="${_line%% *}"
            _num="${_line#* }"
            printf '%s %s' "$_state" "$_num"
            return 0
        fi
    done <<EOF
$_states
EOF
    return 1
}

# Compute the verdict (state) for one worktree. The output discipline
# matches `_gh_flow_verdict` (`gh_flow.sh:152-223`): three lines so the
# caller reads with `IFS= read -r` from a heredoc — no subshell tracing
# trap (auto-memory: pipe-loop subshell pitfall).
#
# Output (3 lines):
#   <state>        — one of: prunable|locked|dirty|pr-open|pr-merged|
#                     pr-closed|merged|ahead|stale|clean
#   <age>          — short human-readable, e.g. "5m"/"2h"/"5d"/"3w"/"-"
#   <next-action>  — single-line hint, e.g. "gwt teardown"
#
# Priority order matches issue #285 §A:
#   prunable > locked > dirty > pr-state > merged > ahead > stale > clean
#
# Args: <wt_path> <branch> <is_main_repo:0|1> [<pr_state>] [<pr_num>]
_gwt_compute_status() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _wt="$1" _branch="$2" _is_main="$3" _pr_state="${4:-}" _pr_num="${5:-}"
    local _age _main_ref _ahead _lock_pid _diff

    # 1. prunable — registered but path missing on disk
    if [ ! -d "$_wt" ]; then
        printf '%s\n%s\n%s\n' "prunable" "-" "gwt prune"
        return 0
    fi

    _age=$(_gwt_age "$_wt")

    # Main worktree never gets state markers — by design (it isn't a thing
    # to "tear down"). Echo clean+"-" so the column lines up.
    if [ "$_is_main" = "1" ]; then
        printf '%s\n%s\n%s\n' "clean" "$_age" "-"
        return 0
    fi

    # 2. locked — claude agent lock present (live or stale, both block teardown)
    if _lock_pid=$(_gwt_claude_lock_pid "$_wt"); then
        printf '%s\n%s\n%s\n' "locked" "$_age" "ps -p ${_lock_pid}"
        return 0
    fi

    # 3. dirty — uncommitted/staged/untracked
    if _gwt_signal_dirty "$_wt"; then
        printf '%s\n%s\n%s\n' "dirty" "$_age" "commit or stash"
        return 0
    fi

    # 4. PR state (only meaningful when --remote populated it)
    case "$_pr_state" in
        OPEN)
            printf '%s\n%s\n%s\n' "pr-open" "$_age" "gh pr view ${_pr_num}"
            return 0
            ;;
        MERGED)
            printf '%s\n%s\n%s\n' "pr-merged" "$_age" "gwt teardown"
            return 0
            ;;
        CLOSED)
            printf '%s\n%s\n%s\n' "pr-closed" "$_age" "gwt teardown --force"
            return 0
            ;;
    esac

    # 5. local merge detection — branch's patches already in main_ref
    _main_ref=$(_gwt_main_ref)
    if [ -n "$_main_ref" ] && [ -n "$_branch" ] \
       && _gwt_branch_merged "$_branch" "$_main_ref"; then
        printf '%s\n%s\n%s\n' "merged" "$_age" "gwt teardown"
        return 0
    fi

    # 6. ahead — has commits beyond main_ref
    if [ -n "$_main_ref" ] && [ -n "$_branch" ]; then
        _ahead=$(_gwt_signal_ahead "$_branch" "$_main_ref")
        if [ -n "$_ahead" ] && [ "$_ahead" -gt 0 ]; then
            printf '%s\n%s\n%s\n' "ahead" "$_age" "git push -u origin ${_branch}"
            return 0
        fi
    fi

    # 7. stale — quiet for >7d (per issue #285 Open Question answer)
    _diff=$(_gwt_age_seconds "$_wt" 2>/dev/null)
    if [ -n "$_diff" ] && [ "$_diff" -gt 604800 ]; then
        printf '%s\n%s\n%s\n' "stale" "$_age" "gwt teardown --force"
        return 0
    fi

    # 8. fallback
    printf '%s\n%s\n%s\n' "clean" "$_age" "-"
}

# Echo the color escape for a state. Caller is responsible for emitting
# UX_RESET. Empty when ANSI is disabled (NO_COLOR / TERM=dumb / test
# mode) — UX_* vars already collapse to empty in that case (see
# ux_lib.sh:31-34), so this function emits nothing extra.
# Args: <state>
_gwt_state_color() {
    case "$1" in
        dirty | prunable)
            printf '%s%s' "${UX_BOLD}" "${UX_ERROR}"
            ;;
        ahead | pr-open)
            printf '%s' "${UX_SUCCESS}"
            ;;
        pr-merged | merged)
            printf '%s' "${UX_PRIMARY}"
            ;;
        pr-closed | stale | locked)
            printf '%s' "${UX_WARNING}"
            ;;
        clean | *)
            printf '%s' "${UX_MUTED}"
            ;;
    esac
}

# ============================================================================
# Worktree list — formatted output with state visibility (issue #285)
# Usage: git_worktree_list [--quick|-q] [--remote|-r] [--help|-h]
#   default       local signals + STATE/AGE/NEXT columns (no network)
#   --quick / -q  legacy output (path/commit/branch only, no signals)
#   --remote / -r adds PR state via one batched `gh pr list` call
# ============================================================================
git_worktree_list() {
    # zsh compatibility — same emulation pattern as remove/teardown
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local mode="auto"
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                ux_header "gwt list - linked worktrees with state"
                ux_info "Usage: gwt list [--quick|-q] [--remote|-r]"
                ux_info ""
                ux_info "  default    STATE/AGE/NEXT columns (local signals only)"
                ux_info "  --quick    legacy output (path/commit/branch only, no signals)"
                ux_info "  --remote   layer PR state via one batched gh CLI call"
                return 0
                ;;
            -q|--quick) mode="quick"; shift ;;
            -r|--remote) mode="remote"; shift ;;
            *)
                ux_error "Unknown flag: $1"
                ux_info "Usage: gwt list [--quick|-q] [--remote|-r]"
                return 1
                ;;
        esac
    done

    if [ "$mode" = "quick" ]; then
        _gwt_list_quick
        return $?
    fi
    _gwt_list_status "$mode"
}

# Probe each registered worktree for orphan/broken states (issue #282) and
# render a warning section if any are found. Catches conditions that the
# regular STATE column cannot derive from porcelain alone:
#   - .git pointer file points to a missing admin dir
#   - .git pointer file points into a foreign repo's admin dir
# Called from both `_gwt_list_quick` and `_gwt_list_status` so the warning
# shows in either mode.
_gwt_render_orphan_warnings() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Resolve this repo's admin dir so the foreign-repo check has a baseline.
    local git_common
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)"
    if [ -n "$git_common" ]; then
        case "$git_common" in
            /*) ;;
            *) git_common="$(cd "$git_common" 2>/dev/null && pwd)" ;;
        esac
        git_common="${git_common%/}"
    fi

    local warn_lines="" warn_count=0
    while IFS= read -r line; do
        case "$line" in
            "worktree "*)
                local wt_path="${line#worktree }"
                local note=""
                if [ ! -d "$wt_path" ]; then
                    note="path missing on disk"
                elif [ -f "$wt_path/.git" ]; then
                    local pointer
                    pointer=$(_gwt_read_gitdir_pointer "$wt_path/.git")
                    if [ -n "$pointer" ]; then
                        if [ ! -d "$pointer" ]; then
                            note=".git -> $pointer (admin dir missing)"
                        elif [ -n "$git_common" ]; then
                            case "$pointer" in
                                "$git_common"/worktrees/*) ;;
                                *) note=".git -> $pointer (foreign repo)" ;;
                            esac
                        fi
                    fi
                fi
                if [ -n "$note" ]; then
                    warn_count=$((warn_count + 1))
                    warn_lines="${warn_lines}  ${wt_path}  [!] ${note}
"
                fi
                ;;
        esac
    done <<EOF
$(git worktree list --porcelain 2>/dev/null)
EOF

    if [ "$warn_count" -gt 0 ]; then
        echo
        ux_warning "$warn_count orphan/broken worktree ref(s):"
        printf '%s' "$warn_lines"
        ux_info "  Recover: rm -rf <path> && gwt prune"
    fi
}

# Legacy list output (preserved for `--quick`). Same shape as the v1
# implementation: path/commit/branch with the remove hint when count > 1.
_gwt_list_quick() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local wt_output wt_count
    wt_output="$(git worktree list)"
    wt_count=$(printf '%s\n' "$wt_output" | wc -l)

    ux_header "Git worktrees ($wt_count)"
    {
        printf '[path] [commit] [branch]\n'
        printf '%s\n' "$wt_output"
    } | column -t

    _gwt_render_orphan_warnings

    if [ "$wt_count" -gt 1 ]; then
        echo
        ux_info "To remove: gwt remove [path]"
    fi
}

# Status-aware list output (default + --remote). Parses
# `git worktree list --porcelain` once, computes per-worktree state via
# _gwt_compute_status, prints a single column-aligned table.
# Args: <mode>  ("auto" — local only, or "remote" — also batch-fetch PR state)
_gwt_list_status() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _mode="$1"
    local _porcelain _pr_states="" _main_wt=""
    local _path="" _branch="" _is_prunable=0 _is_locked=0
    local _wt_count=0

    _porcelain="$(git worktree list --porcelain 2>/dev/null)" || {
        # Use the orphan-aware error reporter from #282 so this list path
        # surfaces the actionable "parent repo gone" diagnostic instead of
        # a bare "not in a git repo" line when the user's $PWD is inside
        # a worktree whose admin dir was deleted.
        _gwt_report_no_git
        return 1
    }

    if [ "$_mode" = "remote" ]; then
        # Bare `$()` (no outer double quotes) — variable assignments don't
        # word-split, and the pre-commit naming hook treats `"...<localfn>..."`
        # as a snake_case-in-user-text violation.
        _pr_states=$(_gwt_remote_pr_states) || _pr_states=""
    fi

    # First worktree in --porcelain output is always the main repo (per
    # git-worktree(1)). Use sed-strip-prefix instead of awk-column so
    # paths containing spaces stay intact (PR #286 review).
    _main_wt="$(printf '%s\n' "$_porcelain" | sed -n 's/^worktree //p;q')"

    # Pre-count for header text (just lines starting with "worktree ").
    _wt_count="$(printf '%s\n' "$_porcelain" | grep -c '^worktree ')"

    ux_header "Git worktrees ($_wt_count)"

    # Build the table in a here-doc fed to column -t. We can't pipe to
    # column -t directly from a while loop without a subshell — and a
    # subshell would lose UX_* color expansion in some shells (and trip
    # the pipe-loop trace trap recorded in auto-memory). So buffer rows
    # into a tmp file, then column -t the whole thing in one call.
    local _table_file
    _table_file="$(mktemp "${TMPDIR:-/tmp}/gwt-ls.XXXXXX")" || {
        ux_error "mktemp failed"
        return 1
    }

    # Header row. ASCII-only words so column -t aligns predictably even
    # with NO_COLOR; styling lives in the data rows below.
    printf 'PATH\tBRANCH\tSTATE\tAGE\tNEXT\n' >>"$_table_file"

    # Stream-parse porcelain. Each record is delimited by a blank line.
    # We accumulate fields until we see the blank, then emit one row.
    while IFS= read -r _line; do
        case "$_line" in
            "worktree "*)
                _path="${_line#worktree }"
                _branch=""
                _is_prunable=0
                _is_locked=0
                ;;
            "branch refs/heads/"*)
                _branch="${_line#branch refs/heads/}"
                ;;
            "detached")
                _branch="(detached)"
                ;;
            "prunable"*)
                _is_prunable=1
                ;;
            "locked"*)
                _is_locked=1
                ;;
            "")
                if [ -n "$_path" ]; then
                    _gwt_emit_row "$_path" "$_branch" "$_main_wt" \
                                  "$_is_prunable" "$_is_locked" \
                                  "$_pr_states" >>"$_table_file"
                    _path=""
                fi
                ;;
        esac
    done <<EOF
$_porcelain
EOF

    # Last record may not be followed by a blank line in porcelain — flush.
    if [ -n "$_path" ]; then
        _gwt_emit_row "$_path" "$_branch" "$_main_wt" \
                      "$_is_prunable" "$_is_locked" \
                      "$_pr_states" >>"$_table_file"
    fi

    column -t -s "$(printf '\t')" <"$_table_file"
    rm -f "$_table_file"

    # Surface orphan/broken refs that the STATE column can't infer from
    # porcelain alone — same probe both modes share (issue #282).
    _gwt_render_orphan_warnings

    if [ "$_wt_count" -gt 1 ]; then
        echo
        if [ "$_mode" != "remote" ]; then
            ux_info "Run 'gwt ls --remote' to include PR state (gh CLI call)."
        fi
        ux_info "Run 'gwt status <name>' for per-worktree diagnostic."
        ux_info "To remove: gwt remove <path|name>"
    fi
}

# Emit one tab-separated table row for a parsed worktree record.
# Looks up the PR state (when remote info passed in), invokes
# _gwt_compute_status for verdict + age + next-action, applies state color.
# Args: <path> <branch> <main_wt> <is_prunable> <is_locked> <pr_states_text>
_gwt_emit_row() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _path="$1" _branch="$2" _main_wt="$3"
    local _is_prunable="$4" _is_locked="$5" _pr_states="$6"
    local _is_main=0 _state="" _age="" _next="" _color=""
    local _pr_state="" _pr_num="" _pr_lookup_out

    [ "$_path" = "$_main_wt" ] && _is_main=1

    # PR lookup — only when remote_pr_states ran and matched the branch.
    if [ -n "$_pr_states" ] && [ -n "$_branch" ] && [ "$_branch" != "(detached)" ]; then
        if _pr_lookup_out=$(_gwt_pr_lookup "$_branch" "$_pr_states"); then
            _pr_state="${_pr_lookup_out%% *}"
            _pr_num="${_pr_lookup_out#* }"
        fi
    fi

    # Porcelain "prunable" overrides — path may exist on disk but git
    # already flagged it for removal (gitdir corruption, manual rm, ...).
    if [ "$_is_prunable" = "1" ]; then
        _state="prunable"
        _age=$(_gwt_age "$_path")
        _next="gwt prune"
    elif [ "$_is_locked" = "1" ]; then
        # Git's own lock predates the claude-agent lock — show it explicitly
        # so the user knows it's a `git worktree lock` (not a stale claude
        # agent). The compute_status path also handles the claude case.
        _state="locked"
        _age=$(_gwt_age "$_path")
        _next="git worktree unlock <path>"
    else
        local _verdict_out
        _verdict_out=$(_gwt_compute_status "$_path" "$_branch" "$_is_main" \
                                            "$_pr_state" "$_pr_num")
        {
            IFS= read -r _state || _state=""
            IFS= read -r _age || _age=""
            IFS= read -r _next || _next=""
        } <<EOF
$_verdict_out
EOF
    fi

    _color=$(_gwt_state_color "$_state")
    printf '%s\t%s\t%s%s%s\t%s\t%s\n' \
        "$_path" "${_branch:-(none)}" \
        "$_color" "$_state" "${UX_RESET}" \
        "$_age" "$_next"
}

# ============================================================================
# Worktree status — single-worktree diagnostic (issue #285)
# Usage: git_worktree_status [<name>]
#   no arg  → status for the worktree containing $PWD
#   <name>  → status for the *-<name>-* match (same matching as `gwt remove`)
#             — fails if multiple match (caller should disambiguate)
# Mirrors `gh-flow status <N>` (`gh_flow.sh:233-350`) so the layout is
# already familiar.
# ============================================================================
git_worktree_status() {
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local _arg="${1:-}"
    case "$_arg" in
        -h|--help)
            ux_header "gwt status - per-worktree diagnostic"
            ux_info "Usage: gwt status [<name>]"
            ux_info ""
            ux_info "  no arg    status for the worktree containing \$PWD"
            ux_info "  <name>    status for *-<name>-* (same as 'gwt remove')"
            return 0
            ;;
    esac

    local _wt_path
    if ! _wt_path=$(_gwt_status_resolve "$_arg"); then
        return 1
    fi

    _gwt_status_render "$_wt_path"
}

# Resolve the target worktree path. Echo it on stdout, or print an error
# and return 1.
# Args: <name-or-empty>
_gwt_status_resolve() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _name="$1"

    if [ -z "$_name" ]; then
        local _toplevel
        _toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || {
            ux_error "gwt status: not inside a git repository"
            return 1
        }
        printf '%s' "$_toplevel"
        return 0
    fi

    # Same matching strategy as git_worktree_remove (`git_worktree.sh:281`),
    # except we anchor on the MAIN repo (not $PWD's toplevel) so the command
    # works from inside any worktree. From a worktree, --show-toplevel returns
    # the worktree path; --git-common-dir's parent is always the main repo.
    local _git_common _main_repo _project _parent _matches="" _match_count=0 _dir
    _git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        ux_error "gwt status: not inside a git repository"
        return 1
    }
    case "$_git_common" in
        /*) ;;
        *) _git_common="$(pwd)/$_git_common" ;;
    esac
    _main_repo="$(dirname "$_git_common")"
    _project="$(basename "$_main_repo")"
    _parent="$(dirname "$_main_repo")"

    for _dir in "$_parent/${_project}-${_name}"-*/; do
        if [ -d "$_dir" ]; then
            _matches="${_matches}${_dir%/}
"
            _match_count=$((_match_count + 1))
        fi
    done

    # The caller invokes us via command substitution `$(_gwt_status_resolve ...)`,
    # so any stdout we emit is captured into the variable instead of reaching
    # the user. Route hint messages to stderr explicitly — ux_error already
    # does this internally, but ux_info defaults to stdout.
    if [ "$_match_count" -eq 0 ]; then
        ux_error "gwt status: no worktree matches '$_name'"
        ux_info "  Run 'gwt list' to see available worktrees." >&2
        return 1
    fi
    if [ "$_match_count" -gt 1 ]; then
        ux_error "gwt status: '$_name' matches $_match_count worktrees — pass an exact path:"
        while IFS= read -r _dir; do
            [ -n "$_dir" ] || continue
            ux_info "  $_dir" >&2
        done <<EOF
$_matches
EOF
        return 1
    fi

    printf '%s' "${_matches%
}"
}

# Render the status box for one worktree path. Shape mirrors
# _gh_flow_status_single (`gh_flow.sh:233-350`): table rows + verdict +
# next action, in that order.
# Args: <wt_path>
_gwt_status_render() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _wt="$1"
    local _toplevel _branch _name _project _is_main=0
    local _head_short _head_subj _head_age _head_line
    local _upstream _ahead _behind _ab_line
    local _porcelain _uncommitted _untracked _u_count _t_count
    local _pr_line _pr_state="" _pr_num=""
    local _lock_pid _lock_line _lock_alive=""
    local _main_ref _verdict_out _state _age _next

    _toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        ux_error "gwt status: not inside a git repository"
        return 1
    }
    # Header should reflect the MAIN repo's project name, even when the
    # user invoked status from inside a worktree. Same git_common-anchor
    # trick as _gwt_status_resolve.
    local _resolve_common _resolve_main
    _resolve_common="$(git rev-parse --git-common-dir 2>/dev/null)"
    case "$_resolve_common" in
        /*) ;;
        *) [ -n "$_resolve_common" ] && _resolve_common="$(pwd)/$_resolve_common" ;;
    esac
    _resolve_main="$(dirname "$_resolve_common" 2>/dev/null)"
    _project="$(basename "${_resolve_main:-$_toplevel}")"
    _name="$(basename "$_wt")"

    if [ ! -d "$_wt" ]; then
        ux_header "gwt status $_name - $_project"
        ux_warning "Worktree path missing on disk: $_wt"
        ux_info "  Run 'gwt prune' to clear the stale registration."
        return 0
    fi

    # Detect main worktree (path == git_common_dir parent).
    local _git_common
    _git_common="$(git -C "$_wt" rev-parse --git-common-dir 2>/dev/null)"
    case "$_git_common" in
        /*) ;;
        *) [ -n "$_git_common" ] && _git_common="$_wt/$_git_common" ;;
    esac
    if [ "$_wt" = "$(dirname "$_git_common" 2>/dev/null)" ]; then
        _is_main=1
    fi

    _branch="$(git -C "$_wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    [ "$_branch" = "HEAD" ] && _branch="(detached)"

    # HEAD: short hash + subject + relative date
    _head_short="$(git -C "$_wt" rev-parse --short HEAD 2>/dev/null)"
    _head_subj="$(git -C "$_wt" log -1 --format=%s HEAD 2>/dev/null)"
    _head_age="$(git -C "$_wt" log -1 --format=%ar HEAD 2>/dev/null)"
    if [ -n "$_head_short" ]; then
        _head_line="$_head_short $_head_subj ($_head_age)"
    else
        _head_line="(no commits)"
    fi

    # Upstream tracking branch
    _upstream="$(git -C "$_wt" rev-parse --abbrev-ref '@{u}' 2>/dev/null)"
    [ -z "$_upstream" ] && _upstream="(none — never pushed)"

    # Working tree state
    _porcelain="$(git -C "$_wt" status --porcelain 2>/dev/null)"
    _u_count=0
    _t_count=0
    if [ -n "$_porcelain" ]; then
        # grep -c always prints a count to stdout, but exits 1 when count == 0.
        # Drop the `|| printf '0'` fallback — it would concatenate "0\n0" on
        # the no-match path and break the integer comparison below.
        _u_count="$(printf '%s\n' "$_porcelain" | grep -cv '^??' 2>/dev/null)"
        _t_count="$(printf '%s\n' "$_porcelain" | grep -c '^??' 2>/dev/null)"
        [ -z "$_u_count" ] && _u_count=0
        [ -z "$_t_count" ] && _t_count=0
    fi
    if [ "$_u_count" -gt 0 ]; then
        _uncommitted="$_u_count file(s)"
    else
        _uncommitted="(none)"
    fi
    if [ "$_t_count" -gt 0 ]; then
        _untracked="$_t_count file(s)"
    else
        _untracked="(none)"
    fi

    # PR lookup for this branch (one network call). gh may be unavailable.
    if [ -n "$_branch" ] && [ "$_branch" != "(detached)" ] \
       && command -v gh >/dev/null 2>&1; then
        local _pr_json _pr_date
        _pr_json="$(gh pr list --head "$_branch" --state all --limit 1 \
            --json number,state,mergedAt,closedAt 2>/dev/null)"
        # Bare `$()` for the same reason as in _gwt_list_status: the
        # pre-commit naming hook flags `"...<localfn>..."` as user-text
        # using snake_case. Variable assignment doesn't need outer quotes.
        _pr_num=$(printf '%s' "$_pr_json" | _gwt_jq_field '.[0].number? // empty')
        _pr_state=$(printf '%s' "$_pr_json" | _gwt_jq_field '.[0].state? // empty')
        if [ -n "$_pr_num" ]; then
            case "$_pr_state" in
                MERGED)
                    # Use parameter expansion to strip the time half — the
                    # jq `split("T")[0]` form would put a `"T"` literal on
                    # the line and trip the pre-commit naming check.
                    _pr_date=$(printf '%s' "$_pr_json" | _gwt_jq_field '.[0].mergedAt? // empty')
                    _pr_date="${_pr_date%%T*}"
                    _pr_line="#$_pr_num (MERGED${_pr_date:+, $_pr_date})"
                    ;;
                CLOSED)
                    _pr_date=$(printf '%s' "$_pr_json" | _gwt_jq_field '.[0].closedAt? // empty')
                    _pr_date="${_pr_date%%T*}"
                    _pr_line="#$_pr_num (CLOSED${_pr_date:+, $_pr_date})"
                    ;;
                OPEN)
                    _pr_line="#$_pr_num (OPEN)"
                    ;;
                *)
                    _pr_line="#$_pr_num ($_pr_state)"
                    ;;
            esac
        else
            _pr_line="(none)"
        fi
    else
        _pr_line="(gh CLI unavailable or detached HEAD — skipped)"
    fi

    # Lock
    if _lock_pid=$(_gwt_claude_lock_pid "$_wt"); then
        if kill -0 "$_lock_pid" 2>/dev/null; then
            _lock_alive="alive"
        else
            _lock_alive="stale"
        fi
        _lock_line="claude agent (pid $_lock_pid, $_lock_alive)"
    elif [ -f "$_git_common/worktrees/$(basename "$_wt")/locked" ]; then
        _lock_line="$(head -1 "$_git_common/worktrees/$(basename "$_wt")/locked" 2>/dev/null)"
        [ -z "$_lock_line" ] && _lock_line="git worktree lock"
    else
        _lock_line="(none)"
    fi

    # Ahead/Behind vs main_ref (computed from main repo cwd; works since the
    # branch ref lives in the shared git_common dir).
    _main_ref=$(_gwt_main_ref)
    _ahead="-"
    _behind="-"
    if [ -n "$_main_ref" ] && [ "$_branch" != "(detached)" ] && [ -n "$_branch" ]; then
        _ahead="$(git rev-list --count "$_main_ref..$_branch" 2>/dev/null || printf '?')"
        _behind="$(git rev-list --count "$_branch..$_main_ref" 2>/dev/null || printf '?')"
    fi
    _ab_line="${_ahead} / ${_behind} (vs ${_main_ref:-?})"

    # Verdict — same matrix as the list view.
    _verdict_out=$(_gwt_compute_status "$_wt" "$_branch" "$_is_main" \
                                       "$_pr_state" "$_pr_num")
    {
        IFS= read -r _state || _state=""
        IFS= read -r _age || _age=""
        IFS= read -r _next || _next=""
    } <<EOF
$_verdict_out
EOF

    ux_header "gwt status $_name - $_project"
    ux_table_row "Path" "$_wt"
    ux_table_row "Branch" "${_branch:-(none)}"
    ux_table_row "HEAD" "$_head_line"
    ux_table_row "Upstream" "$_upstream"
    ux_table_row "Uncommitted" "$_uncommitted"
    ux_table_row "Untracked" "$_untracked"
    ux_table_row "PR" "$_pr_line"
    ux_table_row "Lock" "$_lock_line"
    ux_table_row "Ahead/Behind" "$_ab_line"
    ux_info ""
    local _color
    _color=$(_gwt_state_color "$_state")
    ux_table_row "Verdict" "${_color}${_state}${UX_RESET} (age $_age)"
    if [ "$_is_main" = "1" ]; then
        ux_table_row "Next action" "$_next"
    else
        case "$_state" in
            pr-merged|merged|stale|pr-closed)
                ux_table_row "Next action" "cd $_wt && $_next"
                ;;
            *)
                ux_table_row "Next action" "$_next"
                ;;
        esac
    fi
}

# Tiny jq wrapper: extract a field from JSON via the supplied jq path.
# Falls back to empty string if jq is missing or the JSON is malformed.
# Args: <jq_filter>   (input on stdin)
_gwt_jq_field() {
    if command -v jq >/dev/null 2>&1; then
        jq -r "$1" 2>/dev/null
    else
        cat >/dev/null
    fi
}

# ============================================================================
# Worktree prune — UX wrapper over `git worktree prune`. Rejects positional
# args (git's prune takes only flags), surfacing a friendly hint instead of
# raw `usage: git worktree prune ...` (issue #282).
# Usage: git_worktree_prune [-n|--dry-run] [-v|--verbose] [--expire <when>]
# ============================================================================
git_worktree_prune() {
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local expecting_expire_value=false
    for arg do
        if [ "$expecting_expire_value" = true ]; then
            expecting_expire_value=false
            continue
        fi
        case "$arg" in
            -h|--help)
                ux_header "gwt prune - remove stale worktree refs"
                ux_info "Usage: gwt prune [-n|--dry-run] [-v|--verbose] [--expire <when>]"
                ux_info "  Touches .git/worktrees/ metadata ONLY (no path argument)."
                ux_info "  Removes admin-dir entries whose worktree dir is already gone."
                ux_info "  To delete an actual worktree dir + branch, use:"
                ux_bullet "gwt remove <path|name>  # remove a specific worktree"
                ux_bullet "gwt teardown            # remove the worktree you're inside"
                return 0
                ;;
            -n|--dry-run|-v|--verbose) ;;
            --expire) expecting_expire_value=true ;;
            --expire=*) ;;
            -*)
                ux_error "Unknown option for 'gwt prune': $arg"
                ux_info "Run: gwt prune --help"
                return 1
                ;;
            *)
                ux_error "'gwt prune' does not accept a path argument: $arg"
                ux_info "Did you mean:"
                ux_bullet "gwt remove \"$arg\"        # remove a specific worktree"
                ux_bullet "gwt prune                # prune stale refs (no path)"
                return 1
                ;;
        esac
    done

    git worktree prune "$@"
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
        -h|--help)
            ux_header "gwt remove - remove worktree and branch"
            ux_info "Usage: gwt remove <path|name|all> [--force]"
            ux_info ""
            ux_info "  <path>     full or relative worktree path"
            ux_info "  <name>     worktree name (free-form: issue-11, login-fix, ...)"
            ux_info "             removes ALL worktrees matching *-<name>-*"
            ux_info "  all        remove ALL non-main worktrees"
            ux_info "  --force    force remove + force delete unmerged branch"
            ux_info ""
            ux_info "  Deletes the actual worktree directory + branch."
            ux_info "  To clean stale .git/worktrees/ registry entries (when the"
            ux_info "  directory was already deleted), use: gwt prune"
            return 0
            ;;
        "")
            ux_error "Usage: gwt remove <path|name> [--force]"
            return 1
            ;;
    esac

    local target="$1"
    local force=false
    [ "${2:-}" = "--force" ] && force=true

    # First arg is a flag (e.g. `gwt remove --force`) — user forgot the path/name.
    # Without this guard, `--force` would be misinterpreted as a worktree name
    # and yield a confusing "No worktree found: --force" error.
    case "$target" in
        -*)
            ux_error "Missing <path|name|all>. Got flag: $target"
            ux_info "Did you mean:"
            ux_bullet "gwt remove all $target          # apply '$target' to all worktrees"
            ux_bullet "gwt remove <path|name> $target  # apply '$target' to a specific one"
            return 1
            ;;
        *[*?]*)
            # Wildcards in `target` are confusing UX even when quoted-glob rules
            # render them inert in the for-loop below — refuse explicitly and
            # point the user at the canonical batch entry point.
            ux_error "Wildcards ('*', '?') are not allowed in target: $target"
            ux_info "Use 'gwt remove all' for batch removal."
            return 1
            ;;
    esac

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

    # If target is an existing path, remove directly.
    # Otherwise treat it as a worktree name and resolve to *-<name>-* worktrees.
    if [ -d "$target" ] || [ -e "$target" ]; then
        _gwt_remove_one "$target" "$force"
        return $?
    fi

    # Resolve worktree name to path(s)
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    case "${1:-}" in
        -h|--help)
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
    # %b (not the format string) expands the literal "\n" separators that
    # $excludes accumulates above, without treating patterns as a format.
    printf '/*\n%b' "$excludes" | git -C "$wt_path" sparse-checkout set --stdin

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
# Internal: query GitHub for the PR attached to <branch> and verify its
# merge_commit lives in <main_ref>'s history. Returns 0 only when the PR is
# MERGED and the merge_commit is reachable from main_ref.
#
# Used as a final fallback by _gwt_commits_safe and _gwt_branch_merged for
# the "squash-merged then origin/main progressed past the squash" case
# where neither tree-equivalence nor patch-id can detect that the work is
# already merged (issue #315). gwt status already trusts this signal via
# _gwt_remote_pr_states; teardown should match for a coherent UX.
#
# Soft-fails (returns 1) when gh is missing/unauthenticated, the branch has
# no PR, the PR is not MERGED, or the merge_commit is not yet fetched.
# Callers treat 1 as "no signal" and continue with their existing checks.
#
# Usage: _gwt_pr_merged_into <branch> <main_ref>
# ============================================================================
_gwt_pr_merged_into() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local branch="$1" main_ref="$2"
    [ -n "$branch" ] && [ -n "$main_ref" ] || return 1
    command -v gh >/dev/null 2>&1 || return 1
    # One `gh pr view` invocation, both fields. Two separate calls would
    # mean two forks + two network round-trips per teardown — wasteful in
    # `gwt teardown --all` where this runs once per worktree (PR #316
    # gemini-code-assist review). `.mergeCommit?.oid // ""` is jq's
    # null-safe pattern: an OPEN/CLOSED PR has `mergeCommit == null`, and
    # the optional chain emits "" instead of erroring; the MERGED guard
    # below still rejects non-merged states.
    local pr_info pr_state merge_sha
    pr_info="$(gh pr view "$branch" \
        --json state,mergeCommit \
        --jq '.state + " " + (.mergeCommit?.oid // "")' \
        2>/dev/null)" || return 1
    pr_state="${pr_info%% *}"
    merge_sha="${pr_info#* }"
    [ "$pr_state" = "MERGED" ] && [ -n "$merge_sha" ] || return 1
    git merge-base --is-ancestor "$merge_sha" "$main_ref" 2>/dev/null
}

# ============================================================================
# Internal: check if a branch's patches are in target (rebase/squash merge)
# Usage: _gwt_branch_merged <branch> <target>
# Returns 0 if all patches in <branch> are already in <target>.
# ============================================================================
_gwt_branch_merged() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local branch="$1" target="$2"
    # Rebase merge: every commit is patch-id-equivalent to one already in target.
    if ! git cherry "$target" "$branch" 2>/dev/null | grep -q '^+'; then
        return 0
    fi
    # Squash merge (narrow case): target collapsed N commits to 1, so
    # patch-ids no longer match 1:1 — but the branch's tree is still present
    # in target. `--quiet` is fail-closed: exit 0 only on genuine no-diff;
    # bad ref / git error exits non-zero so a failed comparison is not
    # mistaken for "merged".
    if git diff --quiet "$target" "$branch" 2>/dev/null; then
        return 0
    fi
    # PR API fallback (issue #315): once target progresses past the squash
    # with overlapping changes, the diff is non-empty even though the work
    # is merged. GitHub still knows.
    _gwt_pr_merged_into "$branch" "$target"
}

# ============================================================================
# Internal: print the pid of the claude agent holding <wt_path>'s worktree
# lock (`git worktree lock` reason "claude agent ... (pid N)"). Returns 1 when
# the worktree is unlocked or locked by anything else. Used by status and
# teardown.
# Usage: _gwt_claude_lock_pid <wt_path>
# ============================================================================
_gwt_claude_lock_pid() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local wt_path="$1"
    local git_dir lock_file lock_reason pid

    git_dir="$(git -C "$wt_path" rev-parse --git-dir 2>/dev/null)" || return 1
    case "$git_dir" in
        /*) ;;
        *) git_dir="$wt_path/$git_dir" ;;
    esac
    lock_file="${git_dir}/locked"
    [ -f "$lock_file" ] || return 1

    lock_reason="$(sed -n '1p' "$lock_file" 2>/dev/null)" || return 1
    case "$lock_reason" in
        *"claude agent "*" (pid "*")"*) ;;
        *) return 1 ;;
    esac

    pid="$(printf '%s\n' "$lock_reason" | sed -n 's/.*(pid \([0-9][0-9]*\)).*/\1/p')"
    [ -n "$pid" ] || return 1
    printf '%s\n' "$pid"
}

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_func >/dev/null 2>&1 || return 0
_register_func gwt "Git worktree helper (add/list/spawn/teardown)"
