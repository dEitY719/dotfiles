#!/bin/sh
# shell-common/functions/git_worktree.sh
# Git worktree management functions (split from git.sh)

# Override Oh My Zsh's gwt alias (zsh only)
unalias gwt 2>/dev/null || true

# ============================================================================
# gwt-help — compact help (canonical)
# Usage: gwt-help [section]
# ============================================================================
_gwt_help_summary() {
    ux_info "Usage: gwt-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "add: gwt add <path> [branch] [start]"
    ux_bullet_sub "list: gwt list | gwt ls [--quick|--remote]"
    ux_bullet_sub "remove: gwt remove <path|agent|all> [--force]"
    ux_bullet_sub "prune: gwt prune"
    ux_bullet_sub "spawn: gwt spawn <name> [--task slug] [--base ref] [--tmux|--launch] [--user account]"
    ux_bullet_sub "status: gwt status [<name>]"
    ux_bullet_sub "teardown: gwt teardown [--force] [--keep-branch]"
    ux_bullet_sub "details: gwt-help <section> (example: gwt-help spawn)"
}

_gwt_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "add"
    ux_bullet_sub "list"
    ux_bullet_sub "remove"
    ux_bullet_sub "prune"
    ux_bullet_sub "spawn"
    ux_bullet_sub "status"
    ux_bullet_sub "teardown"
}

_gwt_help_rows_add() {
    ux_table_row "syntax" "gwt add <path> [<new-branch> [<start-point>]]" "Create git-crypt-safe worktree"
    ux_table_row "behavior" "Sparse checkout excludes encrypted paths" "Keeps encrypted layout safe"
}

_gwt_help_rows_list() {
    ux_table_row "syntax" "gwt list | gwt ls [--quick|-q] [--remote|-r]" "List linked worktrees"
    ux_table_row "default" "PATH/BRANCH/STATE/AGE/NEXT columns" "Local signals (no network)"
    ux_table_row "--quick" "path/commit/branch only" "Legacy output"
    ux_table_row "--remote" "Adds PR state via batched gh CLI call" "One network call regardless of N"
    ux_table_row "states" "dirty/ahead/pr-open/pr-merged/merged/..." "See 'gwt-help status' for full list"
}

_gwt_help_rows_status() {
    ux_table_row "syntax" "gwt status [<name>]" "Per-worktree diagnostic"
    ux_table_row "no arg" "status for the worktree containing \$PWD" "Single-worktree mode"
    ux_table_row "<name>" "Matches *-<name>-* like 'gwt remove'" "Fails if multiple match"
    ux_table_row "rows" "Path/Branch/HEAD/Upstream/Uncommitted/PR/Lock/Ahead-Behind" "Mirrors gh-flow status"
    ux_table_row "verdict" "dirty/ahead/pr-open/pr-merged/pr-closed/merged/stale/locked/prunable/clean" "+ Next action hint"
}

_gwt_help_rows_remove() {
    ux_table_row "syntax" "gwt remove <path|name|all> [--force]" "Remove worktree + branch"
    ux_table_row "name mode" "<name> matches *-<name>-*" "Batch remove by worktree name"
    ux_table_row "all mode" "all removes non-main worktrees" "Batch cleanup"
    ux_table_row "force" "--force" "Force remove and branch delete"
}

_gwt_help_rows_prune() {
    ux_table_row "syntax" "gwt prune" "Run: git worktree prune"
}

_gwt_help_rows_spawn() {
    ux_table_row "syntax" "gwt spawn <name> [--task <slug>] [--base <ref>] [--tmux|--launch [--ai <agent>]] [--user <account>]" "Create named worktree"
    ux_table_row "context" "Run from main repo only" "Fails inside a worktree"
    ux_table_row "name" "Free-form slug (required)" "e.g. issue-11, login-fix"
    ux_table_row "--ai" "AI agent (default: claude)" "claude, codex, gemini, opencode, cursor, copilot"
    ux_table_row "--user" "Claude account for --tmux/--launch (only with --ai claude)" "personal, work — default: \$CLAUDE_DEFAULT_ACCOUNT"
    ux_table_row "--tmux" "Runs <agent>-yolo in new tmux pane" "Mutually exclusive with --launch"
    ux_table_row "--launch" "cd into worktree + run <agent>-yolo inline" "Current shell, no tmux"
    ux_table_row "example" "gwt spawn issue-11 --tmux --ai codex" "Free-form name + codex agent"
    ux_table_row "example" "gwt spawn feat --launch" "spawn -> cd -> claude-yolo (one shot)"
    ux_table_row "example" "gwt spawn feat --launch --user work" "spawn -> cd -> claude-yolo --user work"
}

_gwt_help_rows_teardown() {
    ux_table_row "syntax" "gwt teardown [--all|-a|all] [--force] [--keep-branch]" "Cleanup AI worktree(s)"
    ux_table_row "context" "Single mode: run inside a worktree" "Syncs main repo after cleanup"
    ux_table_row "all mode" "Run from main repo or any worktree" "Tears down every non-main worktree"
    ux_table_row "flags" "--force / --keep-branch" "Discard changes / keep branch"
}

_gwt_help_render_section() {
    ux_section "$1"
    "$2"
}

_gwt_help_section_rows() {
    case "$1" in
        add)
            _gwt_help_rows_add
            ;;
        list|ls)
            _gwt_help_rows_list
            ;;
        remove|rm)
            _gwt_help_rows_remove
            ;;
        prune)
            _gwt_help_rows_prune
            ;;
        spawn)
            _gwt_help_rows_spawn
            ;;
        status)
            _gwt_help_rows_status
            ;;
        teardown)
            _gwt_help_rows_teardown
            ;;
        *)
            ux_error "Unknown gwt-help section: $1"
            ux_info "Try: gwt-help --list"
            return 1
            ;;
    esac
}

_gwt_help_full() {
    ux_header "Git Worktree Commands"

    _gwt_help_render_section "Add" _gwt_help_rows_add
    _gwt_help_render_section "List" _gwt_help_rows_list
    _gwt_help_render_section "Remove" _gwt_help_rows_remove
    _gwt_help_render_section "Prune" _gwt_help_rows_prune
    _gwt_help_render_section "Spawn" _gwt_help_rows_spawn
    _gwt_help_render_section "Status" _gwt_help_rows_status
    _gwt_help_render_section "Teardown" _gwt_help_rows_teardown
}

gwt_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _gwt_help_summary
            ;;
        --list|list|section|sections)
            _gwt_help_list_sections
            ;;
        --all|all)
            _gwt_help_full
            ;;
        *)
            _gwt_help_section_rows "$1"
            ;;
    esac
}

# ============================================================================
# gwt — git worktree dispatcher
# Usage: gwt <subcommand> [args...]
# ============================================================================
gwt() {
    case "${1:-}" in
        add)      shift; git_worktree_add "$@" ;;
        list|ls)  shift; git_worktree_list "$@" ;;
        remove|rm) shift; git_worktree_remove "$@" ;;
        prune)    shift; git_worktree_prune "$@" ;;
        spawn)    shift; git_worktree_spawn "$@" ;;
        status)   shift; git_worktree_status "$@" ;;
        teardown) shift; git_worktree_teardown "$@" ;;
        -h|--help|help|"")
            ux_error "Usage: gwt <command> [args...]"
            ux_info "Run: gwt-help"
            return 1
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
        _lock_line="$(cat "$_git_common/worktrees/$(basename "$_wt")/locked" 2>/dev/null | head -1)"
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
                ux_info "  Removes .git/worktrees/<name>/ entries whose path is missing."
                ux_info "  Does NOT take a path argument."
                ux_info "  Targeted removal:"
                ux_bullet "gwt remove <path>      # remove a specific worktree"
                ux_bullet "gwt teardown           # remove the worktree you're inside"
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
# _gwt_yolo_command — agent → yolo command dispatch (issue #243)
#
# Returns the literal command string to run for an agent's yolo mode.
# Bypasses shell alias expansion, which is unreliable inside function
# context — zsh in particular fails to expand `claude-yolo` from inside
# a function body, even via `eval`. Keeping the SSOT here means the
# alias files (claude.sh, codex.sh, gemini.sh, opencode.sh) and the
# launch path stay in sync via grep, not via shell alias resolution.
#
# Output: command string on stdout, exit 0 on known agent.
# Failure: exit 1 on unknown / launch-unsupported agent.
# ============================================================================
_gwt_yolo_command() {
    # `--list` returns the supported agent names so call sites (e.g. the
    # "Supported with --launch" hint) derive from the same SSOT and cannot
    # drift from the case body below.
    #
    # Optional 2nd arg: account name (claude only — multi-account dispatcher,
    # issue #295). When set with --ai claude, the launch command becomes
    # `claude_yolo --user <account>`; other agents ignore it because they do
    # not support multi-account.
    case "$1" in
        --list)   echo "claude, codex, gemini, opencode" ;;
        claude)
            if [ -n "${2-}" ]; then
                echo "claude_yolo --user $2"
            else
                echo "claude_yolo"
            fi
            ;;
        codex)    echo "codex --dangerously-bypass-approvals-and-sandbox" ;;
        gemini)   echo "gemini --approval-mode=yolo --skip-trust" ;;
        opencode) echo "opencode" ;;
        *)        return 1 ;;
    esac
}

# ============================================================================
# Worktree spawn — auto-index, auto-branch, log
# Usage: git_worktree_spawn <name> [--task <slug>] [--base <ref>] [--tmux|--launch] [--ai <agent>] [--user <account>]
# ============================================================================
_git_worktree_spawn_show_help() {
    ux_header "gwt spawn - create a named worktree"
    ux_info "Usage: gwt spawn <name> [--task <slug>] [--base <ref>] [--tmux|--launch] [--ai <agent>] [--user <account>]"
    ux_info ""
    ux_info "Arguments:"
    ux_info "  <name>           Free-form worktree name (required)."
    ux_info "                   Safe chars only: no '/', no spaces, no leading dash."
    ux_info "                   Examples: issue-11, login-fix, feature-x"
    ux_info "  --task <slug>    Add task slug to branch name"
    ux_info "  --base <ref>     Base branch/commit (default: origin/main)"
    ux_info "  --tmux           Auto-create tmux session/window with 3-pane layout"
    ux_info "  --launch         cd into the new worktree and run <agent>-yolo in the"
    ux_info "                   current shell. Mutually exclusive with --tmux."
    ux_info "  --ai <agent>     AI agent for --tmux pane or --launch (default: claude)"
    ux_info "                   Known: claude, codex, gemini, opencode, cursor, copilot"
    ux_info "                   Window name and 'yolo' command follow --ai,"
    ux_info "                   so worktree <name> can be any free-form slug."
    ux_info "  --user <account> Claude account for --tmux/--launch (issue #295)."
    ux_info "                   Only valid with --ai claude (others lack multi-account)."
    ux_info "                   Default: \$CLAUDE_DEFAULT_ACCOUNT (no --user appended)."
    ux_info ""
    ux_info "Examples:"
    ux_info "  gwt spawn issue-11                           # ../<proj>-issue-11-1  wt/issue-11/1"
    ux_info "  gwt spawn login-fix --task auth              # ../<proj>-login-fix-1 wt/login-fix/1-auth"
    ux_info "  gwt spawn issue-11 --tmux                    # tmux window 'claude' runs 'claude-yolo'"
    ux_info "  gwt spawn issue-11 --tmux --ai codex         # tmux window 'codex'  runs 'codex-yolo'"
    ux_info "  gwt spawn feat --launch                      # cd into new worktree + claude-yolo"
    ux_info "  gwt spawn feat --launch --ai codex           # cd + codex-yolo"
    ux_info "  gwt spawn feat --launch --user work          # cd + claude-yolo --user work"
    ux_info "  gwt spawn feat --tmux   --user work          # tmux window runs 'claude-yolo --user work'"
}

git_worktree_spawn() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local task="" base="" name="" use_tmux=0 use_launch=0 agent="claude" account=""

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                _git_worktree_spawn_show_help
                return 0
                ;;
            --task) task="$2"; shift 2 ;;
            --base) base="$2"; shift 2 ;;
            --ai) agent="$2"; shift 2 ;;
            --user) account="$2"; shift 2 ;;
            --tmux) use_tmux=1; shift ;;
            --launch) use_launch=1; shift ;;
            -*)
                ux_error "Unknown option: $1"
                echo ""
                _git_worktree_spawn_show_help
                return 1
                ;;
            *)
                if [ -n "$name" ]; then
                    ux_error "Multiple names given: '$name', '$1' (only one allowed)"
                    echo ""
                    _git_worktree_spawn_show_help
                    return 1
                fi
                name="$1"
                shift
                ;;
        esac
    done

    # Name is required
    if [ -z "$name" ]; then
        ux_error "<name> is required"
        echo ""
        _git_worktree_spawn_show_help
        return 1
    fi

    # Validate name: no path separators, no spaces, no leading dash
    case "$name" in
        -* | */* | *" "*)
            ux_error "Invalid name: '$name' (no '/', no spaces, no leading dash)"
            return 1
            ;;
    esac

    # --tmux and --launch are mutually exclusive (tmux opens a new pane,
    # --launch runs in the current shell — combining them is incoherent).
    if [ "$use_tmux" = 1 ] && [ "$use_launch" = 1 ]; then
        ux_error "--tmux and --launch are mutually exclusive"
        echo ""
        _git_worktree_spawn_show_help
        return 1
    fi

    # Validate --tmux dependency
    if [ "$use_tmux" = 1 ] && ! command -v tmux >/dev/null 2>&1; then
        ux_error "tmux is not installed (required for --tmux)"
        return 1
    fi

    # Validate --ai: must be a known AI agent (only when tmux/launch will use it)
    if { [ "$use_tmux" = 1 ] || [ "$use_launch" = 1 ]; } && ! _ts_known_agent "$agent"; then
        ux_error "Unknown agent: $agent"
        ux_info "Available: claude, codex, gemini, opencode, cursor, copilot"
        return 1
    fi

    # Validate --user (issue #295): only meaningful with claude + tmux/launch.
    # Other agents have no multi-account support so combining them is a typo
    # we want to surface, not silently ignore.
    if [ -n "$account" ]; then
        if [ "$use_tmux" != 1 ] && [ "$use_launch" != 1 ]; then
            ux_error "--user requires --tmux or --launch"
            return 1
        fi
        if [ "$agent" != "claude" ]; then
            ux_error "--user is only supported with --ai claude (got: --ai $agent)"
            return 1
        fi
        # SSOT account validation — reuse claude_yolo's resolver and error shape.
        if ! _claude_resolve_account "$account" >/dev/null 2>&1; then
            ux_error "Unknown account: $account"
            ux_info  "Available: $(_claude_resolve_account --list | tr '\n' ' ')"
            return 1
        fi
    fi

    # Must be inside a git repo, NOT a worktree
    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        _gwt_report_no_git
        return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" != "$git_common" ]; then
        ux_error "Cannot spawn from inside a worktree. Run from the main repo."
        return 1
    fi

    # Compute project, parent, next index
    local project parent next_index=1
    project="$(basename "$(git rev-parse --show-toplevel)")"
    parent="$(dirname "$(git rev-parse --show-toplevel)")"

    for dir in "$parent/${project}-${name}"-*/; do
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

    # Branch name + path must both be unique. A previous teardown may leave a
    # branch (e.g., --keep-branch), so don't rely on directory scan alone.
    local wt_path branch slug=""
    if [ -n "$task" ]; then
        slug=$(printf '%s' "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-30)
    fi
    while :; do
        wt_path="${parent}/${project}-${name}-${next_index}"
        if [ -n "$slug" ]; then
            branch="wt/${name}/${next_index}-${slug}"
        else
            branch="wt/${name}/${next_index}"
        fi

        if [ -d "$wt_path" ]; then
            next_index=$((next_index + 1))
            continue
        fi
        if git rev-parse --verify --quiet "refs/heads/${branch}" >/dev/null 2>&1; then
            next_index=$((next_index + 1))
            continue
        fi
        break
    done

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
    printf '[%s] SPAWN name=%s index=%s path=%s branch=%s base=%s\n' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$name" "$next_index" "$wt_path" "$branch" "$base" \
        >> "${git_common}/ai-worktree-spawn.log"

    ux_header "Worktree spawned"
    ux_info "  Path:   $wt_path"
    ux_info "  Branch: $branch"
    ux_info "  Base:   $base"

    # --- Optional tmux integration ---
    if [ "$use_tmux" = 1 ]; then
        _tmux_add_agent_window "$project" "$agent" "$wt_path" "$account"
        ux_info "  tmux:   session '$project', window '$agent' (runs ${agent}-yolo${account:+ --user $account})"
        if [ -z "$TMUX" ]; then
            tmux attach -t "$project"
        else
            tmux switch-client -t "${project}:${agent}" 2>/dev/null || true
        fi
    elif [ "$use_launch" = 1 ]; then
        # cd in the caller's shell (gwt is a function, not a subshell), then
        # run the agent's yolo command. Resolved via _gwt_yolo_command rather
        # than `eval "<agent>-yolo"`, because zsh does NOT expand aliases from
        # inside a function body even under eval (issue #243). The dispatch
        # table returns the underlying function/command directly, which is
        # always resolvable in either shell.
        local launch_cmd
        if ! launch_cmd=$(_gwt_yolo_command "$agent" "$account"); then
            ux_error "No --launch yolo command for agent: $agent"
            ux_info "Supported with --launch: $(_gwt_yolo_command --list)"
            return 1
        fi
        ux_info "  launch: cd \"$wt_path\" && $launch_cmd"
        cd "$wt_path" || { ux_error "Cannot cd to $wt_path"; return 1; }
        eval "$launch_cmd"
    else
        ux_info ""
        ux_info "  cd $wt_path"
    fi
}

# ============================================================================
# Internal: check if current HEAD's commits are safe to discard
# Returns 0 (safe) if: upstream matches, or HEAD is in origin/main,
# or all patches are already in origin/main (rebase/squash merge).
# ============================================================================
_gwt_commits_safe() {
    local local_rev remote_rev
    local_rev="$(git rev-parse HEAD)"

    # 1. Upstream tracking branch matches exactly
    remote_rev="$(git rev-parse '@{u}' 2>/dev/null || echo "no-upstream")"
    if [ "$remote_rev" != "no-upstream" ] && [ "$local_rev" = "$remote_rev" ]; then
        return 0
    fi

    # 2. HEAD is an ancestor of origin/main (fast-forward or true merge)
    local main_ref="origin/main"
    git rev-parse --verify --quiet "$main_ref" >/dev/null 2>&1 || main_ref="origin/master"
    if git merge-base --is-ancestor HEAD "$main_ref" 2>/dev/null; then
        return 0
    fi

    # 3. All patches already applied via rebase/squash merge (patch-id comparison)
    # git cherry marks already-applied commits with '-', unapplied with '+'.
    # If grep finds no '+' line, every HEAD commit is patch-id-equivalent to
    # something already in main_ref → safe.
    if ! git cherry "$main_ref" HEAD 2>/dev/null | grep -q '^+'; then
        return 0
    fi

    # 4. Upstream exists but remote branch was deleted (PR merged + branch auto-deleted)
    if [ "$remote_rev" = "no-upstream" ]; then
        # No upstream ever set — could be genuinely unpushed
        # Check if there are any commits beyond the merge-base with main
        local ahead
        ahead="$(git rev-list --count "$main_ref"..HEAD 2>/dev/null || echo "999")"
        if [ "$ahead" = "0" ]; then
            return 0
        fi
    fi

    return 1
}

# ============================================================================
# Internal: check if a branch's patches are in target (rebase/squash merge)
# Usage: _gwt_branch_merged <branch> <target>
# Returns 0 if all patches in <branch> are already in <target>.
# ============================================================================
_gwt_branch_merged() {
    local branch="$1" target="$2"
    # No '+' line from git cherry → all patches already in target.
    ! git cherry "$target" "$branch" 2>/dev/null | grep -q '^+'
}

# ============================================================================
# Internal: pick the best merge-detection target. Prefer origin/<main> if
# fetched, else fall back to local <main> (stale detection better than none).
# Usage: _gwt_merge_target <main_branch>
# ============================================================================
_gwt_merge_target() {
    local main_branch="$1"
    if git rev-parse --verify --quiet "origin/$main_branch" >/dev/null 2>&1; then
        printf '%s\n' "origin/$main_branch"
    else
        printf '%s\n' "$main_branch"
    fi
}

# ============================================================================
# Internal: render an actionable "unpushed commits" diagnostic.
# Usage: _gwt_report_unpushed <branch>
# ============================================================================
_gwt_report_unpushed() {
    local branch="$1"
    local main_ref="origin/main"
    git rev-parse --verify --quiet "$main_ref" >/dev/null 2>&1 || main_ref="origin/master"

    local upstream ahead remote_branch_ref remote_branch_exists
    upstream="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "(none)")"
    ahead="$(git rev-list --count "$main_ref"..HEAD 2>/dev/null || echo "?")"
    remote_branch_ref="origin/$branch"
    if git rev-parse --verify --quiet "refs/remotes/$remote_branch_ref" >/dev/null 2>&1; then
        remote_branch_exists=true
    else
        remote_branch_exists=false
    fi

    ux_error "Local commits on '$branch' are not in $main_ref ($ahead ahead, upstream: $upstream)."
    if [ "$remote_branch_exists" = true ]; then
        ux_info "  Remote branch exists: $remote_branch_ref"
        ux_info "  Next:   merge/cherry-pick these commits, or use --force to discard locally."
    else
        ux_info "  Push:   git push -u origin $branch"
    fi
    ux_info "  Or:     gwt teardown --force   # discard local commits in this worktree"
    if [ "$ahead" != "?" ] && [ "$ahead" != "0" ]; then
        ux_info "  Commits not in $main_ref (newest first):"
        git log --no-color --format='    %h %s' "$main_ref"..HEAD 2>/dev/null | head -10
    fi
}

# ============================================================================
# Worktree teardown — remove worktree, sync main, delete branch, log
# Usage: git_worktree_teardown [--all|-a|all] [--force] [--keep-branch]
# ============================================================================
git_worktree_teardown() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force=false keep_branch=false all_mode=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                ux_header "gwt teardown - AI worktree cleanup"
                ux_info "Usage: gwt teardown [--all|-a|all] [--force] [--keep-branch]"
                ux_info ""
                ux_info "Options:"
                ux_info "  --all, -a, all tear down every non-main worktree (run from main"
                ux_info "                 repo or inside any worktree)"
                ux_info "  --force        discard uncommitted changes and force remove"
                ux_info "  --keep-branch  keep the branch after removing worktree"
                return 0
                ;;
            --all|-a|all) all_mode=true; shift ;;
            --force) force=true; shift ;;
            --keep-branch) keep_branch=true; shift ;;
            -*)
                ux_error "Unknown option: $1. Use --help for usage."
                return 1
                ;;
            *)
                # Detect whether current pwd is main repo or inside a worktree
                # so we can tailor the error guidance to the mistake actually made.
                local _gwt_common _gwt_dir _gwt_in_wt=false _gwt_loc
                _gwt_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
                    _gwt_report_no_git
                    return 1
                }
                _gwt_dir="$(git rev-parse --git-dir 2>/dev/null)"
                [ "$_gwt_dir" != "$_gwt_common" ] && _gwt_in_wt=true
                _gwt_loc="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

                ux_error "'gwt teardown' does not accept a path argument."
                echo ""
                if [ "$_gwt_in_wt" = true ]; then
                    # Scenario B: user is already in a worktree but still typed a path
                    ux_info "You are already inside a worktree: $_gwt_loc"
                    ux_info "Drop the path argument and just run:"
                    echo ""
                    ux_bullet "gwt teardown"
                else
                    # Scenario A: user is in the main repo (most common mistake)
                    ux_info "You are in:  main repo ($_gwt_loc)"
                    ux_info "You passed:  $1"
                    echo ""
                    ux_warning "'gwt teardown' is SELF-CLEANUP — it tears down the worktree"
                    ux_warning "you are currently inside (cd into it first, then run)."
                    echo ""
                    ux_info "Did you mean:"
                    ux_bullet "cd \"$1\" && gwt teardown     # full cleanup: remove + sync main + delete branch"
                    ux_bullet "gwt remove \"$1\"             # remove worktree only (no main sync, no branch delete)"
                    ux_bullet "gwt teardown --all          # tear down every non-main worktree at once"
                fi
                return 1
                ;;
        esac
    done

    # Batch mode: tear down every non-main worktree.
    if [ "$all_mode" = true ]; then
        _gwt_teardown_all "$force" "$keep_branch"
        return $?
    fi

    # Must be inside a worktree
    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        _gwt_report_no_git
        return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" = "$git_common" ]; then
        ux_error "Not inside a worktree. Nothing to tear down."
        ux_info "  Use 'gwt teardown --all' to tear down every linked worktree."
        return 1
    fi

    _gwt_teardown_one_inplace "$force" "$keep_branch"
    return $?
}

# ============================================================================
# Internal: tear down the worktree containing $PWD (single-mode pipeline).
# Caller MUST already be inside the target worktree. Performs pre-flight
# checks, removes the worktree, ff-syncs main, deletes the branch, logs.
# Cd's to main repo on success, restores cwd to original worktree on failure.
# Args: <force> <keep_branch>
# ============================================================================
_gwt_claude_lock_pid() {
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

_gwt_teardown_one_inplace() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force="$1" keep_branch="$2"

    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        _gwt_report_no_git
        return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" = "$git_common" ]; then
        ux_error "Not inside a worktree. Nothing to tear down."
        return 1
    fi

    # Collect info before pre-flights so lock checks can run before dirty-state
    # exits and leave stale Claude agent locks cleaned up for the next attempt.
    local wt_path branch wt_name main_repo
    wt_path="$(git rev-parse --show-toplevel)"
    branch="$(git rev-parse --abbrev-ref HEAD)"
    wt_name="$(basename "$wt_path")"
    main_repo="$(dirname "$git_common")"

    local claude_lock_pid="" claude_lock_live=false
    if claude_lock_pid=$(_gwt_claude_lock_pid "$wt_path"); then
        if kill -0 "$claude_lock_pid" 2>/dev/null; then
            claude_lock_live=true
            if [ "$force" != true ]; then
                ux_error "Cannot remove worktree: $wt_path"
                ux_warning "Claude agent lock is active (pid $claude_lock_pid). Another Claude session may still be using this worktree."
                ux_info "  Inspect:  ps -p $claude_lock_pid"
                ux_info "  Override: gwt teardown --force"
                ux_info "            (only after confirming the Claude session is safe to discard)"
                return 1
            fi
        else
            ux_info "Stale Claude agent lock detected (pid $claude_lock_pid is not running) - unlocking worktree."
            if ! git worktree unlock "$wt_path" 2>/dev/null; then
                ux_warning "Failed to unlock stale Claude agent lock; git will report details if removal fails."
            fi
        fi
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

    # Pre-flight: untracked files.
    # `git worktree remove` (without --force) refuses when untracked files
    # exist. Catch it here with a message the user can act on, instead of
    # letting the later remove call fail with a stderr we'd have to surface.
    if git status --porcelain 2>/dev/null | grep -q '^??'; then
        if [ "$force" = true ]; then
            ux_warning "Discarding untracked files (--force)"
        else
            ux_error "Untracked files present — git worktree remove will refuse."
            ux_info "  Inspect:  git status --short"
            ux_info "  Clean:    git clean -fd"
            ux_info "  Override: gwt teardown --force"
            return 1
        fi
    fi

    # Pre-flight: unpushed commits.
    # (A) Capture fetch stderr so failures surface the actual cause, not a
    # misleading "network?" blurb. Real reason (auth, hook, URL, etc.) wins.
    local _gwt_fetch_err_file="${TMPDIR:-/tmp}/gwt-fetch.$$.err"
    if ! git fetch origin 2>"$_gwt_fetch_err_file" >/dev/null; then
        ux_warning "git fetch origin failed (non-blocking); using local refs for safety checks."
        if [ -s "$_gwt_fetch_err_file" ]; then
            sed 's/^/    /' "$_gwt_fetch_err_file" >&2
        fi
    fi
    rm -f "$_gwt_fetch_err_file"
    # Checks (in order): upstream match → ancestor of origin/main → patch-id (rebase merge)
    if ! _gwt_commits_safe; then
        if [ "$force" = true ]; then
            ux_warning "Discarding unpushed commits (--force)"
        else
            # (E) Actionable diagnostic: show ahead count, upstream state,
            # push command, and the list of unpushed commits.
            _gwt_report_unpushed "$(git rev-parse --abbrev-ref HEAD)"
            return 1
        fi
    fi

    # Switch to main repo
    cd "$main_repo" || { ux_error "Cannot cd to $main_repo"; return 1; }

    # Remove worktree. Capture stderr so the actual git reason (locked, dirty
    # submodule, untracked residuals, etc.) reaches the user instead of being
    # swallowed — same pattern as the fetch-stderr capture above. Choose the
    # remove command upfront from $force so a single error-handling block
    # covers both paths. On failure, cd back into $wt_path so the user stays
    # in the worktree they asked to remove (we already cd'd to $main_repo
    # above) and can investigate.
    local _gwt_rm_err_file="${TMPDIR:-/tmp}/gwt-rm.$$.err"
    local _gwt_rm_exit=0
    if [ "$force" = true ]; then
        if [ "$claude_lock_live" = true ]; then
            ux_warning "Removing Claude agent locked worktree (--force)."
            git worktree remove -f -f "$wt_path" 2>"$_gwt_rm_err_file" || _gwt_rm_exit=$?
        else
            git worktree remove --force "$wt_path" 2>"$_gwt_rm_err_file" || _gwt_rm_exit=$?
        fi
    else
        git worktree remove "$wt_path" 2>"$_gwt_rm_err_file" || _gwt_rm_exit=$?
    fi

    # Auto-recovery for the submodule-block case. `git worktree remove` refuses
    # any tree that contains submodules, even when their working trees are
    # untouched — the AI-worktree workflow re-clones submodules on the next
    # spawn, so their populated state is disposable. The parent worktree has
    # already passed every dirty-state pre-flight above (uncommitted, staged,
    # untracked, unpushed), so retrying with --force here only adds permission
    # to drop populated submodule contents — exactly what we want. Without
    # this, every teardown of a repo with submodules would force the user to
    # rerun manually, which is what issue #211 was filed against.
    if [ "$_gwt_rm_exit" -ne 0 ] && [ "$force" != true ] \
       && grep -q "working trees containing submodules cannot be moved or removed" "$_gwt_rm_err_file" 2>/dev/null; then
        ux_info "Submodules detected — retrying removal (parent worktree already verified clean)."
        : > "$_gwt_rm_err_file"
        if git worktree remove --force "$wt_path" 2>"$_gwt_rm_err_file"; then
            _gwt_rm_exit=0
        else
            _gwt_rm_exit=$?
        fi
    fi

    if [ "$_gwt_rm_exit" -ne 0 ]; then
        local _gwt_submodule_blocked=false
        if grep -q "working trees containing submodules cannot be moved or removed" "$_gwt_rm_err_file" 2>/dev/null; then
            _gwt_submodule_blocked=true
        fi

        if [ "$force" = true ]; then
            ux_error "Failed to remove worktree: $wt_path"
        else
            ux_error "Cannot remove worktree: $wt_path"
        fi
        if [ -s "$_gwt_rm_err_file" ]; then
            ux_info "  git says:"
            sed 's/^/    /' "$_gwt_rm_err_file" >&2
        fi
        if [ "$_gwt_submodule_blocked" = true ]; then
            # Auto-recovery already retried with --force above; reaching here
            # means even --force could not remove this worktree (locked
            # submodule, permissions, gitlink corruption, etc.). The user has
            # to investigate manually.
            ux_warning "  Git blocked removal even with --force — a submodule is in an unusual state."
            local _gwt_submodule_paths _gwt_submodule_path _gwt_submodule_count=0
            _gwt_submodule_paths="$(git -C "$wt_path" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')"
            if [ -n "$_gwt_submodule_paths" ]; then
                ux_info "  Submodules in this repository:"
                while IFS= read -r _gwt_submodule_path; do
                    [ -n "$_gwt_submodule_path" ] || continue
                    ux_info "    - $_gwt_submodule_path"
                    _gwt_submodule_count=$((_gwt_submodule_count + 1))
                    [ "$_gwt_submodule_count" -ge 3 ] && break
                done <<EOF
$_gwt_submodule_paths
EOF
            fi
            ux_info "  Inspect:  git -C \"$wt_path\" submodule foreach 'git status --short'"
            ux_info "  Locks:    git -C \"$wt_path\" submodule foreach 'git config --get core.bare; git status'"
        elif [ "$force" != true ]; then
            ux_info "  Inspect:  git -C \"$wt_path\" status --short"
            ux_info "  Clean:    git -C \"$wt_path\" clean -fd"
            ux_info "  Override: gwt teardown --force"
            ux_info "            (run from inside: $wt_path)"
        fi
        rm -f "$_gwt_rm_err_file"
        cd "$wt_path" 2>/dev/null || true
        return 1
    fi
    rm -f "$_gwt_rm_err_file"
    git worktree prune

    # Sync main BEFORE branch delete.
    local main_branch="main"
    if ! git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
        main_branch="master"
    fi
    # (F) -q suppresses "Your branch is behind 'origin/<main>' by N commits"
    # which git checkout prints to stdout (unsilenceable via 2>/dev/null).
    if ! git checkout -q "$main_branch" 2>/dev/null; then
        ux_error "Failed to checkout $main_branch in main repository."
        return 1
    fi
    # (B) Replace `git pull origin <main>` with local `git merge --ff-only
    # origin/<main>`. We already fetched above — no second network round-trip,
    # no rebase-merge surprises under pull.rebase=true. Diverged local main is
    # reported clearly rather than collapsed into "network?".
    local _gwt_ff_err_file="${TMPDIR:-/tmp}/gwt-ff.$$.err"
    local main_sync_ok=true
    if git rev-parse --verify --quiet "origin/$main_branch" >/dev/null 2>&1; then
        if ! git merge --ff-only "origin/$main_branch" 2>"$_gwt_ff_err_file" >/dev/null; then
            main_sync_ok=false
            ux_error "Main sync failed — git merge --ff-only origin/$main_branch"
            if [ -s "$_gwt_ff_err_file" ]; then
                sed 's/^/    /' "$_gwt_ff_err_file" >&2
            fi
            ux_info "  Local '$main_branch' has diverged from origin/$main_branch."
            ux_info "  Resolve manually (rebase / reset) before spawning new worktrees from local '$main_branch'."
        fi
    else
        main_sync_ok=false
        ux_warning "origin/$main_branch not found — skipping ff-sync (fetch likely failed)."
    fi
    rm -f "$_gwt_ff_err_file"

    # (D) Prefer origin/<main> over local <main> for rebase-merge detection.
    # Local <main> can be stale when the ff-only sync above failed — exactly
    # the scenario where we most need merge detection to still fire.
    local merge_target
    merge_target=$(_gwt_merge_target "$main_branch")

    # Delete branch
    if [ "$keep_branch" = true ]; then
        ux_info "Branch kept: $branch (--keep-branch)"
    elif git branch -d "$branch" 2>/dev/null; then
        : # deleted successfully (fast-forward or true merge)
    elif _gwt_branch_merged "$branch" "$merge_target"; then
        # Rebase/squash merge: commits are in main_ref but SHAs differ.
        git branch -D "$branch" 2>/dev/null
        ux_success "Branch deleted (rebase-merged): $branch"
    elif [ "$force" = true ]; then
        git branch -D "$branch" 2>/dev/null
        ux_success "Branch force-deleted: $branch"
    else
        ux_warning "Branch '$branch' not fully merged. Use --force or --keep-branch."
    fi

    # Log
    printf '[%s] TEARDOWN worktree=%s branch=%s path=%s\n' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$wt_name" "$branch" "$wt_path" \
        >> "$(git rev-parse --git-common-dir)/ai-worktree-spawn.log"

    # (C-2) Strict exit: if main is not in sync with origin, report partial
    # teardown and return non-zero so callers (CI, hooks, chained aliases)
    # notice. Worktree removal and branch delete still ran.
    if [ "$main_sync_ok" = true ]; then
        ux_success "Teardown complete"
        ux_info "  Removed: $wt_path"
        ux_info "  Now on:  $main_branch"
        return 0
    fi

    ux_warning "Teardown partial — worktree removed, main NOT in sync with origin/$main_branch"
    ux_info "  Removed: $wt_path"
    ux_info "  Now on:  $main_branch (out of sync)"
    return 1
}

# ============================================================================
# Internal: tear down every non-main worktree (best-effort).
# Args: <force> <keep_branch>
# Returns 0 if all teardowns succeed, 1 if any failed (or aborted, or no repo).
# ============================================================================
_gwt_teardown_all() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force="$1" keep_branch="$2"

    # Must be inside a git repo (main or any worktree).
    # Keep `|| { ...; }` on one line so the closing brace does not appear at
    # line-start; library_purity_check tracks brace depth via `^\s*\}` and
    # would otherwise treat this as the enclosing function's close, falsely
    # flagging the `read -r` below as top-level interactive code.
    git rev-parse --git-common-dir >/dev/null 2>&1 || { _gwt_report_no_git; return 1; }

    # Resolve main worktree and collect non-main worktrees from a single
    # `git worktree list --porcelain` snapshot — one fork instead of two,
    # and both parses see the same repo state.
    local porcelain main_wt all_wts="" all_count=0
    porcelain="$(git worktree list --porcelain)"
    IFS= read -r main_wt <<EOF
$porcelain
EOF
    main_wt="${main_wt#worktree }"

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
$porcelain
EOF

    if [ "$all_count" -eq 0 ]; then
        ux_info "No worktrees to tear down."
        return 0
    fi

    ux_warning "About to tear down $all_count worktree(s):"
    while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        ux_info "  $wt"
    done <<EOF
$all_wts
EOF

    if [ "$force" != true ]; then
        if ! ux_confirm "Proceed with teardown?" "n"; then
            ux_info "Aborted."
            return 1
        fi
    fi

    # Park in main repo so loop iterations have a stable cwd between runs.
    cd "$main_wt" 2>/dev/null || { ux_error "Cannot cd to main repo: $main_wt"; return 1; }

    local ok_count=0 fail_count=0 failed_wts=""
    while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        ux_header "Tearing down: $wt"
        if [ ! -d "$wt" ]; then
            ux_warning "  Path missing on disk — skipping (run 'gwt prune' to clean stale refs)."
            fail_count=$((fail_count + 1))
            failed_wts="${failed_wts}${wt} (missing)
"
            continue
        fi
        # Split across lines: naming_check.sh greedy-matches `".*<func>.*"` on
        # a single line, so keeping `"$wt"` and `"$force"` from sandwiching the
        # helper name on one physical line avoids a false-positive flag.
        if ( cd "$wt" \
             && _gwt_teardown_one_inplace "$force" "$keep_branch" ); then
            ok_count=$((ok_count + 1))
        else
            fail_count=$((fail_count + 1))
            failed_wts="${failed_wts}${wt}
"
        fi
        # Restore cwd to main_wt — _gwt_teardown_one_inplace ran in subshell,
        # so caller's cwd is unchanged, but defensively re-anchor.
        cd "$main_wt" 2>/dev/null || true
    done <<EOF
$all_wts
EOF

    ux_header "Teardown summary"
    ux_info "  Succeeded: $ok_count"
    ux_info "  Failed:    $fail_count"
    if [ "$fail_count" -gt 0 ]; then
        ux_info "  Failed worktrees:"
        while IFS= read -r wt; do
            [ -n "$wt" ] || continue
            ux_info "    $wt"
        done <<EOF
$failed_wts
EOF
        return 1
    fi
    ux_success "All worktrees torn down."
    return 0
}

alias gwt-help='gwt_help'
