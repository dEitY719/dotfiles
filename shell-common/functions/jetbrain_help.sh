#!/bin/sh
# shell-common/functions/jetbrain_help.sh
# jetbrain-help topic (launcher lives in tools/integrations/jetbrain.sh)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_jetbrain_help_summary() {
    ux_info "Usage: jetbrain-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "commands: pycharm [args...]"
    ux_bullet_sub "config: PYCHARM_BIN | JETBRAIN_HOME"
    ux_bullet_sub "details: jetbrain-help <section>  (example: jetbrain-help config)"
}

_jetbrain_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "commands"
    ux_bullet_sub "config"
}

_jetbrain_help_rows_commands() {
    ux_table_row "pycharm [args...]" "Launch PyCharm" "Binary resolved on every call"
}

_jetbrain_help_rows_config() {
    ux_table_row "\$PYCHARM_BIN" "Explicit binary path" "Checked first"
    ux_table_row "\$JETBRAIN_HOME" "Install root (default ~/application)" "Newest pycharm-*/bin/pycharm wins"
    ux_bullet "Fallback: ~/application/pycharm-2025.2.0.1/bin/pycharm"
}

_jetbrain_help_section_rows() {
    case "$1" in
        commands | cmds | usage) _jetbrain_help_rows_commands ;;
        config | env) _jetbrain_help_rows_config ;;
        *)
            ux_error "Unknown jetbrain-help section: $1"
            ux_info "Try: jetbrain-help --list"
            return 1
            ;;
    esac
}

_jetbrain_help_full() {
    ux_header "JetBrains IDE Launcher"
    ux_section "Commands"
    _jetbrain_help_rows_commands
    ux_section "Configuration"
    _jetbrain_help_rows_config
}

jetbrain_help() {
    case "${1:-}" in
        "" | -h | --help | help) _jetbrain_help_summary ;;
        --list | list | section | sections) _jetbrain_help_list_sections ;;
        --all | all) _jetbrain_help_full ;;
        *) _jetbrain_help_section_rows "$1" ;;
    esac
}

alias jetbrain-help='jetbrain_help'
