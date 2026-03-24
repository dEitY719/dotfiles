#!/bin/sh
# shell-common/functions/redis_help.sh

redis_help() {
    ux_header "Redis Service Management"

    ux_section "Commands"
    ux_table_row "redis-server-ctl <action>" "Manage service" "start, stop, restart, status"
    ux_table_row "redis-ping" "Health check" "PING/PONG test"
    ux_table_row "redis-info [section]" "Server info" "server, memory, clients, etc."
    ux_table_row "redis-monitor" "Live monitor" "Real-time command stream"
    ux_table_row "redis-dbsize" "Key count" "Current DB key count"
    ux_table_row "redis-keys [pattern]" "Scan keys" "SCAN with glob pattern"
    ux_table_row "redis-flush <db|all>" "Flush data" "Clear current DB or all DBs"
    ux_table_row "redis-config-get <param>" "Config value" "Get runtime config"
    ux_table_row "redis-slowlog [count]" "Slow queries" "Recent slow log entries"
    ux_table_row "redis-clients" "Client list" "Connected clients info"
    ux_table_row "redis-memory" "Memory stats" "Memory usage details"
    ux_table_row "install-redis" "Install Redis" "Interactive installer for WSL"

    ux_section "Environment"
    ux_table_row "REDIS_DEFAULT_HOST" "Server host" "Default: 127.0.0.1"
    ux_table_row "REDIS_DEFAULT_PORT" "Server port" "Default: 6379"
}

alias redis-help='redis_help'
