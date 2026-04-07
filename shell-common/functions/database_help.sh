#!/bin/sh
# shell-common/functions/database_help.sh
# Bundle: database tool help functions

# --- mysql_help (from mysql_help.sh) ---

mysql_help() {
    ux_header "MySQL Service Management"

    ux_section "Service Commands"
    ux_table_row "mysql_list" "List configured services" "Show all database connections"
    ux_table_row "mysql_dmc_dev" "Connect to dev database" "Use .my.cnf config"
    ux_table_row "mysql_dmc_test" "Connect to test database" "Use .my.cnf config"
    ux_table_row "mysql_cmd <svc> <cmd>" "Execute SQL command" "databases, tables, version, describe, status, etc."
    ux_table_row "mysql_server <action>" "Manage service" "start, stop, restart, status, reload"
}

# --- psql_help (from psql_help.sh) ---

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
