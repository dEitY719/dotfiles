#!/bin/sh
# shell-common/functions/mysql_help.sh

mysql_help() {
    ux_header "MySQL Service Management"

    ux_section "Service Commands"
    ux_table_row "mysql_list" "List configured services" "Show all database connections"
    ux_table_row "mysql_dmc_dev" "Connect to dev database" "Use .my.cnf config"
    ux_table_row "mysql_dmc_test" "Connect to test database" "Use .my.cnf config"
    ux_table_row "mysql_cmd <svc> <cmd>" "Execute SQL command" "databases, tables, version, describe, status, etc."
    ux_table_row "mysql_server <action>" "Manage service" "start, stop, restart, status, reload"
}
