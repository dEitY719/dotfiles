#!/bin/sh
# shell-common/functions/cc_help.sh

cc_help() {
    ux_header "Claude Code Usage Commands"

    ux_section "Installation"
    ux_bullet "Global prefix: npm install -g ccusage --prefix=\$HOME/.npm-global"

    ux_section "Commands"
    ux_table_row "ccd" "ccusage daily --breakdown" "Token usage by model"
    ux_table_row "ccs" "ccusage session --sort tokens" "Session analysis"
    ux_table_row "ccb" "ccusage blocks --live" "Cache hit ratio (live)"
}

alias cc-help='cc_help'
