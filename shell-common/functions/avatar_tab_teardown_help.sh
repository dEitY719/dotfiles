#!/bin/sh
# shell-common/functions/avatar_tab_teardown_help.sh
# Help for avatar-tab-teardown (logic: tools/custom/avatar_tab_teardown.sh, #2320).

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_avatar_tab_teardown_help_summary() {
    ux_info "Usage: avatar-tab-teardown [--yes] [--worktree] [--force] [--repo <slug>] [--issue <N>]"
    ux_bullet "Closes finished herdr tabs of the unattended pipelines: iw (issue-watcher), mt (merge-train), mv (post-merge-verify)"
    ux_bullet_sub "default is a dry run: prints the candidates, closes nothing"
    ux_bullet "sections: options, rules (avatar-tab-teardown-help <section>)"
}

_avatar_tab_teardown_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "options"
    ux_bullet_sub "rules"
}

_avatar_tab_teardown_help_rows_options() {
    ux_table_row "avatar-tab-teardown" "Dry run" "List closable and skipped tabs, change nothing"
    ux_table_row "--yes" "Close" "herdr tab close every closable tab"
    ux_table_row "--worktree" "Remove" "After closing: gwt remove the iw/mv worktree when clean and pushed/merged (never mt)"
    ux_table_row "--force" "Override" "Ignore agent status and issue/PR state; gwt remove --force (current tab still skipped)"
    ux_table_row "--repo <slug>" "Scope" "Only tabs of this repo (owner/repo or repo)"
    ux_table_row "--issue <N>" "Scope" "Only tabs of issue/PR <N> (excludes mt)"
}

_avatar_tab_teardown_help_rows_rules() {
    ux_table_row "ownership" "Agent name" "iw-<repo>-issue-<N> / mt-<repo> / mv-<repo>-pr-<N>; label or mv scratch cwd as fallback"
    ux_table_row "hand-made tab" "Never" "issue-<N> / pr-<N> labels alone are not candidates"
    ux_table_row "all kinds" "Idle" "No agent in the tab is working or blocked"
    ux_table_row "iw" "Closed" "Issue <N> is CLOSED on GitHub (lookup failure: WARN, not closed)"
    ux_table_row "mv" "Merged" "PR <N> is MERGED"
    ux_table_row "mt" "Idle only" "The next merge-train tick recreates the tab"
    ux_table_row "current tab" "Skip" "The tab this command runs in is never closed"
    ux_table_row "repo" "Watch list" "Slug resolved via avatar-watched-repos list; mt falls back to its checkout's origin"
}

_avatar_tab_teardown_help_full() {
    _avatar_tab_teardown_help_summary
    ux_section "options"
    _avatar_tab_teardown_help_rows_options
    ux_section "rules"
    _avatar_tab_teardown_help_rows_rules
}

avatar_tab_teardown_help() {
    case "${1:-}" in
    "" | -h | --help | help) _avatar_tab_teardown_help_full ;;
    --list | list | section | sections) _avatar_tab_teardown_help_list_sections ;;
    --all | all) _avatar_tab_teardown_help_full ;;
    options | opts) _avatar_tab_teardown_help_rows_options ;;
    rules) _avatar_tab_teardown_help_rows_rules ;;
    *)
        ux_error "Unknown avatar-tab-teardown-help section: $1"
        ux_info "Try: avatar-tab-teardown-help --list"
        return 1
        ;;
    esac
}

alias avatar-tab-teardown-help='avatar_tab_teardown_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help avatar_tab_teardown_help "[Development] close finished iw/mt/mv herdr tabs (+ worktrees)" development
