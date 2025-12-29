#!/bin/sh
# shell-common/functions/mysql_help.sh
# mysql Help - shared between bash and zsh

mysql_help() {
    ux_header "MySQL Service Management"

    ux_section "Service Commands"
    ux_table_row "mysql_list" "List configured services" "Show all database connections"
    ux_table_row "mysql_dmc_dev" "Connect to dev database" "Use .my.cnf config"
    ux_table_row "mysql_dmc_test" "Connect to test database" "Use .my.cnf config"
    ux_table_row "mysql_cmd <svc> <cmd>" "Execute SQL command" "databases, tables, version, describe, status, etc."
    ux_table_row "mysql_server <action>" "Manage service" "start, stop, restart, status, reload"
    echo ""

    ux_section "Common Workflows"
    ux_bullet "Show databases: mysql_cmd dmc_dev databases"
    ux_bullet "Show tables: mysql_cmd dmc_dev tables"
    ux_bullet "Check MySQL version: mysql_cmd dmc_dev version"
    ux_bullet "Check service status: mysql_server status"
    echo ""
}
