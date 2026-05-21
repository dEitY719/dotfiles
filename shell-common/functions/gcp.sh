#!/bin/sh
# shell-common/functions/gcp.sh
#
# Type 2A dispatcher for the gcp_* cherry-pick family. See
# docs/.ssot/command-design-pattern.md §4 (Type 2A) and §1 (naming).
#
# Public surface:
#   gcp scan   [base] [src] [--author=<name|all>]
#   gcp theirs <commit>...
#   gcp ours   <commit>...
#   gcp author <range> [author]
#   gcp pick   <commit>...
#   gcp [-h | --help | help [section|--list|--all]]
#
# Deprecated backward-compat (Phase 1 — issue #697):
#   gcp_scan / gcp-scan / gcp_theirs / gcp_ours / gcp_author  → 'gcp <verb>'
#   gcp <committish>                                          → 'gcp pick'
#                                                              + ux_warning

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Override Oh My Zsh's gcp alias (zsh only) — mirrors git_worktree.sh:9.
# Without this, OMZ's `alias gcp='git cherry-pick'` is still active when
# this file is sourced, and zsh expands aliases at parse time, turning
# `gcp() {` into `git cherry-pick () {` → "parse error near '()'".
# Issue #700 (c36db10 회귀).
unalias gcp 2>/dev/null || true

# ----------------------------------------------------------------------------
# Heuristic: $1 is a resolvable commit-ish. Used by the bare-form
# `gcp <committish>` bridge so muscle-memory keeps working with a deprecation
# warning. rev-parse handles HEAD~3, branch^, abbreviated SHAs, refs, etc. —
# regex hex matching alone would miss those.
# ----------------------------------------------------------------------------
_gcp_committish_p() {
    [ -n "${1-}" ] || return 1
    git rev-parse --verify "$1^{commit}" >/dev/null 2>&1
}

# ----------------------------------------------------------------------------
# Family-shared pre-flight: refuse to start a new cherry-pick while one is
# already in progress, and tell the user how to recover. SSOT for the check
# `_gcp_scan` introduced inline (gcp_scan.sh) — other verbs reuse the same
# helper so the warning + recovery hint are identical across the family.
# Returns 1 (and emits the recovery hint) when a cherry-pick is in progress;
# 0 otherwise. PR #698 review feedback (gemini-code-assist).
# ----------------------------------------------------------------------------
_gcp_assert_no_cherry_pick() {
    git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 || return 0
    ux_error "Cherry-pick currently in progress!"
    ux_info  "Resolve first with one of:"
    ux_bullet "git cherry-pick --continue   # after fixing conflicts"
    ux_bullet "git cherry-pick --skip       # to drop the current commit"
    ux_bullet "git cherry-pick --abort      # to cancel"
    return 1
}

# ----------------------------------------------------------------------------
# Internal: cherry-pick with optional -X <strategy>. SSOT for theirs/ours so
# the two wrappers stay one-liners (Type 2A §9 SRP).
# Args: <strategy:""|theirs|ours> <commit>...
# ----------------------------------------------------------------------------
_gcp_strategy_pick() {
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi
    local strategy="$1"
    shift

    if [ $# -eq 0 ]; then
        local cmd_name="gcp pick"
        local desc="Cherry-pick one or more commits"
        if [ -n "$strategy" ]; then
            cmd_name="gcp $strategy"
            desc="Cherry-pick with '$strategy' conflict strategy"
        fi
        ux_usage "$cmd_name" "<commit-id> [commit-id2] ..." "$desc"
        ux_bullet "$cmd_name abc1234"
        [ -n "$strategy" ] && ux_warning "Conflicts will use $strategy changes"
        return 1
    fi

    _gcp_assert_no_cherry_pick || return 1

    local commit failed=0
    for commit in "$@"; do
        if [ -n "$strategy" ]; then
            if git cherry-pick -X "$strategy" "$commit"; then
                ux_success "Cherry-pick (-X $strategy) succeeded: $commit"
            else
                ux_error "Cherry-pick (-X $strategy) failed: $commit"
                ux_info  "Resolve with: git cherry-pick --continue | --skip | --abort"
                failed=1
                break
            fi
        else
            if git cherry-pick "$commit"; then
                ux_success "Cherry-pick succeeded: $commit"
            else
                ux_error "Cherry-pick failed: $commit"
                ux_info  "Resolve with: git cherry-pick --continue | --skip | --abort"
                failed=1
                break
            fi
        fi
    done
    return $failed
}

_gcp_pick()   { _gcp_strategy_pick "" "$@"; }
_gcp_theirs() { _gcp_strategy_pick "theirs" "$@"; }
_gcp_ours()   { _gcp_strategy_pick "ours" "$@"; }

# ----------------------------------------------------------------------------
# Cherry-pick all commits by <author> in <range>. Default author is dEitY719
# (matches the SSOT in _gcp_scan / gcp_scan.sh).
# ----------------------------------------------------------------------------
_gcp_author() {
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi
    local commit_range="${1-}"
    local author="${2:-dEitY719}"

    if [ -z "$commit_range" ]; then
        ux_usage "gcp author" "<commit-range> [author-name]" "Cherry-pick commits by specific author"
        ux_bullet "gcp author 751e304..7ffcbd4"
        ux_bullet "gcp author 751e304..7ffcbd4 dEitY719"
        ux_warning "Format: <start>..<end> or <start>^..<end>"
        return 1
    fi

    _gcp_assert_no_cherry_pick || return 1

    local commits
    commits=$(git log --author="$author" --no-merges --reverse --pretty=format:"%h" "$commit_range" 2>/dev/null)

    if [ -z "$commits" ]; then
        ux_error "No commits found by '$author' in range $commit_range"
        return 1
    fi

    ux_info "Cherry-picking commits by '$author' in range $commit_range:"
    echo "$commits"
    echo ""
    # Word-splitting on $commits is intentional — newline-separated SHAs
    # become separate args to _gcp_pick, which then drives the per-commit
    # success/failure UX + recovery hint loop (PR #698 review).
    # shellcheck disable=SC2086
    _gcp_pick $commits
}

# ----------------------------------------------------------------------------
# Help — standalone, mirrors gwt_help's section/list/full structure.
# ----------------------------------------------------------------------------
_gcp_help_summary() {
    ux_info "Usage: gcp help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "scan    gcp scan [base] [src] [--author=<name|all>]   compare & cherry-pick missing commits"
    ux_bullet_sub "theirs  gcp theirs <commit>...                         cherry-pick with -X theirs (incoming wins)"
    ux_bullet_sub "ours    gcp ours <commit>...                           cherry-pick with -X ours (current wins)"
    ux_bullet_sub "author  gcp author <range> [author]                    cherry-pick commits by author"
    ux_bullet_sub "pick    gcp pick <commit>...                           bare cherry-pick (one or more)"
    ux_bullet_sub "details gcp help <section>  (example: gcp help scan)"
}

_gcp_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "scan"
    ux_bullet_sub "theirs"
    ux_bullet_sub "ours"
    ux_bullet_sub "author"
    ux_bullet_sub "pick"
}

_gcp_help_rows_scan() {
    ux_table_row "syntax" "gcp scan [base] [src] [--author=<name|all>]" "Compare & pick missing commits"
    ux_table_row "default" "main <- upstream/main, author=dEitY719" "Filter by author by default"
    ux_table_row "--author=all" "show all authors" "Bypass filter"
    ux_table_row "behavior" "detects duplicates (same subject in base)" "Skips already-applied commits"
    ux_table_row "behavior" "contiguous range -> bulk cherry-pick" "Non-contiguous -> individual"
}

_gcp_help_rows_theirs() {
    ux_table_row "syntax" "gcp theirs <commit>..." "Cherry-pick with -X theirs"
    ux_table_row "conflict" "incoming (cherry-picked) changes win" ""
}

_gcp_help_rows_ours() {
    ux_table_row "syntax" "gcp ours <commit>..." "Cherry-pick with -X ours"
    ux_table_row "conflict" "current branch changes win" ""
}

_gcp_help_rows_author() {
    ux_table_row "syntax" "gcp author <range> [author]" "Cherry-pick commits by author"
    ux_table_row "default author" "dEitY719" ""
    ux_table_row "range format" "<start>..<end> or <start>^..<end>" ""
}

_gcp_help_rows_pick() {
    ux_table_row "syntax" "gcp pick <commit>..." "Bare cherry-pick (one or more)"
    ux_table_row "note" "replaces deprecated bare 'gcp <commit>'" "bare form bridges with deprecation warning"
}

_gcp_help_render_section() {
    ux_section "$1"
    "$2"
}

_gcp_help_section_rows() {
    case "$1" in
        scan)    _gcp_help_rows_scan ;;
        theirs)  _gcp_help_rows_theirs ;;
        ours)    _gcp_help_rows_ours ;;
        author)  _gcp_help_rows_author ;;
        pick)    _gcp_help_rows_pick ;;
        *)
            ux_error "Unknown gcp help section: $1"
            ux_info "Try: gcp help --list"
            return 1
            ;;
    esac
}

_gcp_help_full() {
    ux_header "Git Cherry-Pick Commands"
    _gcp_help_render_section "Scan"   _gcp_help_rows_scan
    _gcp_help_render_section "Theirs" _gcp_help_rows_theirs
    _gcp_help_render_section "Ours"   _gcp_help_rows_ours
    _gcp_help_render_section "Author" _gcp_help_rows_author
    _gcp_help_render_section "Pick"   _gcp_help_rows_pick
}

gcp_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _gcp_help_summary
            ;;
        --list|list|section|sections)
            _gcp_help_list_sections
            ;;
        --all|all)
            _gcp_help_full
            ;;
        *)
            _gcp_help_section_rows "$1"
            ;;
    esac
}

# ----------------------------------------------------------------------------
# gcp — dispatcher (Type 2A). _gcp_scan is defined in gcp_scan.sh; the loader
# sources both files alphabetically (gcp.sh -> gcp_scan.sh) so the function
# is in scope by the time a user types 'gcp scan'.
# ----------------------------------------------------------------------------
gcp() {
    case "${1:-}" in
        scan)    shift; _gcp_scan   "$@" ;;
        theirs)  shift; _gcp_theirs "$@" ;;
        ours)    shift; _gcp_ours   "$@" ;;
        author)  shift; _gcp_author "$@" ;;
        pick)    shift; _gcp_pick   "$@" ;;
        -h|--help|help|"")
            [ $# -gt 0 ] && shift
            gcp_help "$@"
            ;;
        *)
            if _gcp_committish_p "$1"; then
                ux_warning "Deprecated: bare 'gcp <commit>' will be removed in a future release."
                ux_info    "Use: gcp pick $*"
                _gcp_pick "$@"
            else
                ux_error "Unknown command: $1"
                ux_info  "Run: gcp help"
                return 1
            fi
            ;;
    esac
}

# Deprecated backward-compat aliases (Phase 1 — see issue #697 "Out of Scope")
alias gcp_scan='gcp scan'
alias gcp-scan='gcp scan'
alias gcp_theirs='gcp theirs'
alias gcp_ours='gcp ours'
alias gcp_author='gcp author'
alias gcp-help='gcp_help'
