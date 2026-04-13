#!/bin/sh
# shell-common/functions/database_help.sh
# Bundle: database tool help functions

# --- mysql_help (from mysql_help.sh) ---

_mysql_help_summary() {
    ux_info "Usage: mysql-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "service: mysql_list | mysql_dmc_dev | mysql_dmc_test | mysql_cmd | mysql_server"
    ux_bullet_sub "details: mysql-help <section>  (example: mysql-help service)"
}

_mysql_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "service"
}

_mysql_help_rows_service() {
    ux_table_row "mysql_list" "List configured services" "Show all database connections"
    ux_table_row "mysql_dmc_dev" "Connect to dev database" "Use .my.cnf config"
    ux_table_row "mysql_dmc_test" "Connect to test database" "Use .my.cnf config"
    ux_table_row "mysql_cmd <svc> <cmd>" "Execute SQL command" "databases, tables, version, describe, status, etc."
    ux_table_row "mysql_server <action>" "Manage service" "start, stop, restart, status, reload"
}

_mysql_help_render_section() {
    ux_section "$1"
    "$2"
}

_mysql_help_section_rows() {
    case "$1" in
        service|commands)
            _mysql_help_rows_service
            ;;
        *)
            ux_error "Unknown mysql-help section: $1"
            ux_info "Try: mysql-help --list"
            return 1
            ;;
    esac
}

_mysql_help_full() {
    ux_header "MySQL Service Management"

    _mysql_help_render_section "Service Commands" _mysql_help_rows_service
}

mysql_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _mysql_help_summary
            ;;
        --list|list)
            _mysql_help_list_sections
            ;;
        --all|all)
            _mysql_help_full
            ;;
        *)
            _mysql_help_section_rows "$1"
            ;;
    esac
}

alias mysql-help='mysql_help'

# --- psql_help (from psql_help.sh) ---

_psql_help_summary() {
    ux_info "Usage: psql-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "primary: psql_list | psql_bootstrap | psql_sync | psql_add | psql_del"
    ux_bullet_sub "lowlevel: psql_db | psql_user"
    ux_bullet_sub "details: psql-help <section>  (example: psql-help primary)"
}

_psql_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "primary"
    ux_bullet_sub "lowlevel"
}

_psql_help_rows_primary() {
    ux_table_row "psql_list" "List Services" "Show all configured connections"
    ux_table_row "psql_bootstrap" "Create New" "Full Setup: Create DB, User, Grant & Save"
    ux_table_row "psql_sync" "Sync DBs" "Scan server and add existing DBs to config"
    ux_table_row "psql_add" "Add Link" "Manually add a shortcut for existing DB"
    ux_table_row "psql_del" "Remove" "Remove service (and optionally drop DB)"
}

_psql_help_rows_lowlevel() {
    ux_table_row "psql_db" "DB Ops" "list, create, delete, grant"
    ux_table_row "psql_user" "User Ops" "list, create, attr, passwd, delete"
}

_psql_help_render_section() {
    ux_section "$1"
    "$2"
}

_psql_help_section_rows() {
    case "$1" in
        primary|main)
            _psql_help_rows_primary
            ;;
        lowlevel|low|management)
            _psql_help_rows_lowlevel
            ;;
        *)
            ux_error "Unknown psql-help section: $1"
            ux_info "Try: psql-help --list"
            return 1
            ;;
    esac
}

_psql_help_full() {
    ux_header "PostgreSQL Manager"

    _psql_help_render_section "Primary Commands" _psql_help_rows_primary
    _psql_help_render_section "Low-Level Management" _psql_help_rows_lowlevel

    # Show services table
    psql_list
}

psql_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _psql_help_summary
            ;;
        --list|list)
            _psql_help_list_sections
            ;;
        --all|all)
            _psql_help_full
            ;;
        *)
            _psql_help_section_rows "$1"
            ;;
    esac
}

alias psql-help='psql_help'

# --- redis_help (from redis_help.sh) ---

redis_help() {
    ux_header "Redis Service Management"

    ux_section "Commands"
    ux_table_row "redis-server-ctl <action>" "Manage service" "start, stop, restart, status"
    ux_table_row "redis-ping" "Health check" "PING/PONG test"
    ux_table_row "redis-info [section]" "Server info" "server, memory, clients, etc."
    ux_table_row "redis-monitor" "Live monitor" "Real-time command stream"
    ux_table_row "redis-dbsize" "Key count" "Current DB key count"
    ux_table_row "redis-keys [pattern] [limit]" "Scan keys" "SCAN with glob pattern (default: 20)"
    ux_table_row "redis-flush <db|all>" "Flush data" "Clear current DB or all DBs"
    ux_table_row "redis-config-get <param>" "Config value" "Get runtime config"
    ux_table_row "redis-slowlog [count]" "Slow queries" "Recent slow log entries"
    ux_table_row "redis-clients" "Client list" "Connected clients info"
    ux_table_row "redis-memory" "Memory stats" "Memory usage details"
    ux_table_row "install-redis" "Install Redis" "Interactive installer for WSL"

    ux_section "Environment"
    ux_table_row "REDISCLI_AUTH" "Password" "Auto-auth for all commands"
    ux_table_row "REDIS_DEFAULT_HOST" "Server host" "Default: 127.0.0.1"
    ux_table_row "REDIS_DEFAULT_PORT" "Server port" "Default: 6379"
}

alias redis-help='redis_help'
