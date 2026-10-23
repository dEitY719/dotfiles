#!/bin/sh
# shell-common/functions/avatar_issue_watcher.sh
# Wrapper function: delegates to tools/custom/avatar_issue_watcher.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

avatar_issue_watcher() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/avatar_issue_watcher.sh "$@"
}

alias avatar-issue-watcher='avatar_issue_watcher'

# Help topic. Also keeps `my-help avatar-issue-watcher` from falling through to
# running a real tick. Full detail stays in the tool's own --help (usage SSOT).
_avatar_issue_watcher_help_summary() {
    ux_info "Usage: avatar-issue-watcher-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "commands: run modes (tick, --dry-run, --status, watch)"
    ux_bullet_sub "examples: manual runs, watch list, periodic runs (aicron/crontab)"
    ux_info "Full cycle, caps, gate, watch list and state paths: avatar-issue-watcher --help"
}

_avatar_issue_watcher_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "commands"
    ux_bullet_sub "examples"
}

_avatar_issue_watcher_help_rows_commands() {
    ux_table_row "avatar-issue-watcher" "Tick" "Dispatch assigned open issues to /gh-flow:wave (cron)"
    ux_table_row "avatar-issue-watcher --dry-run" "Preview" "Print what a tick would dispatch, change nothing"
    ux_table_row "avatar-issue-watcher --status" "Status" "Rate-limit gate, saturation, gh search state"
    ux_table_row "avatar-issue-watcher watch list" "Watch" "Show the watch list file and its entries"
    ux_table_row "avatar-issue-watcher watch add [owner/repo]" "Watch" "Add/update an entry (--path P, --host H; default: cwd repo)"
    ux_table_row "avatar-issue-watcher watch remove [owner/repo]" "Watch" "Drop an entry (default: cwd repo)"
    ux_table_row "avatar-issue-watcher --help" "Help" "Full cycle, caps and gate rules"
}

_avatar_issue_watcher_help_rows_examples() {
    ux_table_row "avatar-issue-watcher --dry-run" "Manual" "Preview one tick without dispatching"
    ux_table_row "avatar-issue-watcher --status" "Manual" "Show gate, saturation and search state"
    ux_table_row "cd ~/dotfiles && avatar-issue-watcher" "Manual" "cwd mode: tick only this repo"
    ux_table_row "avatar-issue-watcher --cwd ~/dotfiles" "Manual" "Same tick, started from any directory"
    ux_table_row "avatar-issue-watcher watch list" "Watch" "Show the watch list"
    ux_table_row "cd ~/dotfiles && avatar-issue-watcher watch add" "Watch" "Add the cwd repo"
    ux_table_row "avatar-issue-watcher watch add dEitY719/gh-verify-skills --path ~/para/project/skills" "Watch" "Add a repo with its checkout path"
    ux_table_row "avatar-issue-watcher watch remove dEitY719/equinest" "Watch" "Drop a repo"
    ux_table_row "aicron add avatar-issue-watcher --schedule '*/4 * * * *'" "Periodic" "Install the shipped aicron job"
    ux_table_row "aicron status avatar-issue-watcher --json | jq .last_exit" "Periodic" "Exit code of the last run"
    ux_table_row "aicron run avatar-issue-watcher --dry-run" "Periodic" "Run the job once by hand"
    ux_table_row "crontab: */4 * * * * avatar-issue-watcher --cwd ~ >> ~/.local/state/avatar-issue-watcher/cron.log 2>&1" "Periodic" "Plain crontab line"
    ux_bullet "Note: inside a git repo without --cwd it runs in cwd mode (that repo only, no watch list)"
    ux_bullet "Note: from cron, pass --cwd or start in \$HOME so the watch list is used"
}

_avatar_issue_watcher_help_full() {
    ux_header "avatar-issue-watcher"
    ux_section "Commands"
    _avatar_issue_watcher_help_rows_commands
    ux_section "Examples"
    _avatar_issue_watcher_help_rows_examples
}

avatar_issue_watcher_help() {
    case "${1:-}" in
        "" | -h | --help | help) _avatar_issue_watcher_help_summary ;;
        --list | list | section | sections) _avatar_issue_watcher_help_list_sections ;;
        --all | all) _avatar_issue_watcher_help_full ;;
        commands | cmds) _avatar_issue_watcher_help_rows_commands ;;
        examples | example) _avatar_issue_watcher_help_rows_examples ;;
        *)
            ux_error "Unknown avatar-issue-watcher-help section: $1"
            ux_info "Try: avatar-issue-watcher-help --list"
            return 1
            ;;
    esac
}

alias avatar-issue-watcher-help='avatar_issue_watcher_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help avatar_issue_watcher_help "[Development] issue-watcher cron tick (assigned issues -> /gh-flow:wave)" development
