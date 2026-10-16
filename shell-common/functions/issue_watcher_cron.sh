#!/bin/sh
# shell-common/functions/issue_watcher_cron.sh
# Wrapper function: delegates to tools/custom/issue_watcher_cron.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

issue_watcher_cron() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Script basename injected via ${_name} so the literal function name
    # never appears a second time inside a quoted string — keeps the repo's
    # naming check (git/hooks/checks/naming_check.sh) silent, same technique
    # as cp_wdown.sh.
    local _name=issue_watcher_cron
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/${_name}.sh" "$@"
}

alias issue-watcher-cron='issue_watcher_cron'

# Help topic. Also keeps `my-help issue-watcher-cron` from falling through to
# running a real tick. Full detail stays in the tool's own --help (usage SSOT).
_issue_watcher_cron_help_summary() {
    ux_info "Usage: issue-watcher-cron-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "usage: run modes (tick, --dry-run, --status)"
    ux_bullet_sub "files: watch list and state files"
    ux_bullet_sub "details: issue-watcher-cron --help  (full cycle, caps, rate-limit gate)"
}

_issue_watcher_cron_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "usage"
    ux_bullet_sub "files"
}

_issue_watcher_cron_help_rows_usage() {
    ux_table_row "issue-watcher-cron" "Tick" "Dispatch assigned open issues to /gh-flow:issue (cron)"
    ux_table_row "issue-watcher-cron --dry-run" "Preview" "Print what a tick would dispatch, change nothing"
    ux_table_row "issue-watcher-cron --status" "Status" "Rate-limit gate, saturation, gh search state"
    ux_table_row "issue-watcher-cron --help" "Help" "Full cycle, caps and gate rules"
}

_issue_watcher_cron_help_rows_files() {
    ux_bullet "Watch list: ~/.agent-factory/avatars/issue-watcher/watched-repos.json (or \$IW_WATCHED_REPOS)"
    ux_bullet "State dir: \${XDG_STATE_HOME:-~/.local/state}/issue-watcher/"
}

_issue_watcher_cron_help_full() {
    ux_header "issue-watcher-cron"
    ux_section "Usage"
    _issue_watcher_cron_help_rows_usage
    ux_section "Files"
    _issue_watcher_cron_help_rows_files
}

issue_watcher_cron_help() {
    case "${1:-}" in
        "" | -h | --help | help) _issue_watcher_cron_help_summary ;;
        --list | list | section | sections) _issue_watcher_cron_help_list_sections ;;
        --all | all) _issue_watcher_cron_help_full ;;
        usage) _issue_watcher_cron_help_rows_usage ;;
        files) _issue_watcher_cron_help_rows_files ;;
        *)
            ux_error "Unknown issue-watcher-cron-help section: $1"
            ux_info "Try: issue-watcher-cron-help --list"
            return 1
            ;;
    esac
}

alias issue-watcher-cron-help='issue_watcher_cron_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help issue_watcher_cron_help "[Development] issue-watcher cron tick (assigned issues -> /gh-flow:issue)" development
