#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gwt_help.sh
# gwt (git worktree) help — split from git_worktree.sh (#2156)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# ============================================================================
# gwt-help — compact help (canonical)
# Usage: gwt-help [section]
# ============================================================================
_gwt_help_summary() {
    ux_info "Usage: gwt-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "add      gwt add <path> [branch] [start]              create worktree"
    ux_bullet_sub "list     gwt list|ls [--quick|--remote]               list worktrees"
    ux_bullet_sub "remove   gwt remove <path|name|all> [--force]         delete worktree dir + branch"
    ux_bullet_sub "prune    gwt prune                                    clean stale .git/worktrees/ refs (no path)"
    ux_bullet_sub "spawn    gwt spawn <name> [--task|--base|--tmux|...]  create named worktree (AI workflow)"
    ux_bullet_sub "status   gwt status [<name>]                          per-worktree diagnostic"
    ux_bullet_sub "teardown gwt teardown [--all [-r]] [--force] [...]    cleanup current/all worktree(s)"
    ux_bullet_sub "details: gwt-help <section>  (example: gwt-help spawn)"
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
    ux_table_row "--ai" "AI agent (default: claude)" "claude, codex, agy, opencode, cursor, copilot"
    ux_table_row "--user" "Claude account for --tmux/--launch (only with --ai claude)" "personal, work — default: \$CLAUDE_DEFAULT_ACCOUNT"
    ux_table_row "--tmux" "Runs <agent>-yolo in new tmux pane" "Mutually exclusive with --launch"
    ux_table_row "--launch" "cd into worktree + run <agent>-yolo inline" "Current shell, no tmux"
    ux_table_row "example" "gwt spawn issue-11 --tmux --ai codex" "Free-form name + codex agent"
    ux_table_row "example" "gwt spawn feat --launch" "spawn -> cd -> claude-yolo (one shot)"
    ux_table_row "example" "gwt spawn feat --launch --user work" "spawn -> cd -> claude-yolo --user work"
}

_gwt_help_rows_teardown() {
    ux_table_row "syntax" "gwt teardown [--all|-a|all] [--recursive|-r] [--force] [--keep-branch]" "Cleanup AI worktree(s)"
    ux_table_row "context" "Single mode: run inside a worktree" "Syncs main repo after cleanup"
    ux_table_row "all mode" "Run from main repo or any worktree" "Tears down every non-main worktree"
    ux_table_row "recursive" "--all --recursive|-r from a parent dir" "Every main repo directly under \$PWD (one prompt)"
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

alias gwt-help='gwt_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help gwt_help "[Development] Git worktree command guide" development
