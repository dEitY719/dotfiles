#!/bin/sh
# shell-common/functions/psql_help.sh

psql_help() {
    if [[ $# -gt 0 ]]; then
        # Legacy/Direct mode support: psql_help <service> <cmd>
        local svc=""
        shift
        local sql_cmd="$*"
        PGSERVICE="$svc" psql -c "$sql_cmd"
        return
    fi

    ux_header "PostgreSQL Manager"

    ux_section "Primary Commands"
    ux_table_row "psql_list" "List Services" "Show all configured connections"
    ux_table_row "psql_bootstrap" "Create New" "Full Setup: Create DB, User, Grant & Save"
    ux_table_row "psql_sync" "Sync DBs" "Scan server and add existing DBs to config"
    ux_table_row "psql_add" "Add Link" "Manually add a shortcut for existing DB"
    ux_table_row "psql_del" "Remove" "Remove service (and optionally drop DB)"

    ux_section "Low-Level Management"
    ux_table_row "psql_db" "DB Ops" "list, create, delete, grant"
    ux_table_row "psql_user" "User Ops" "list, create, attr, passwd, delete"

    # Show services table
    psql_list
}

alias psql-help='psql_help'
