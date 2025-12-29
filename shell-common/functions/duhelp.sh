#!/bin/sh
# shell-common/functions/duhelp.sh
# duHelp - shared between bash and zsh

duhelp() {
    ux_header "Disk Usage Helper (du aliases)"

    ux_section "Aliases"
    ux_table_row "dus" "du -sh ." "Current dir summary"
    ux_table_row "dud" "du -sh *" "Subdir summary (sorted)"
    ux_table_row "dsql" "du .sql" "SQL dump sizes"
    ux_table_row "dubig" "du top 10" "Top 10 largest items"
    echo ""

    ux_info "Tip: -h option means 'human-readable' (K, M, G)"
    echo ""
}
