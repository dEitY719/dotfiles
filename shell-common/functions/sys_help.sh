#!/bin/sh
# shell-common/functions/sys_help.sh
# sysHelp - shared between bash and zsh

sys_help() {
    ux_header "System Management Commands"

    ux_section "Process Management"
    ux_table_row "psg" "ps aux | grep" "Find process"
    ux_table_row "kill9" "kill -9" "Force kill"
    ux_table_row "psa" "ps aux" "List all processes"
    echo ""

    ux_section "Network"
    ux_table_row "ports" "ss -tulanp" "Show open ports"
    ux_table_row "myip" "curl ipecho.net" "Public IP"
    ux_table_row "localip" "hostname -I" "Local IP"
    ux_table_row "ping" "ping -c 5" "Ping (5 times)"
    echo ""

    ux_section "Monitoring"
    ux_table_row "top" "htop" "Process monitor"
    ux_table_row "meminfo" "free -m" "Memory usage"
    ux_table_row "cpuinfo" "lscpu" "CPU info"
    ux_table_row "diskusage" "df -h" "Disk usage"
    echo ""

    ux_section "Package Management (APT)"
    ux_table_row "update" "apt update" "Update lists"
    ux_table_row "upgrade" "apt upgrade" "Upgrade packages"
    ux_table_row "install" "apt install" "Install package"
    ux_table_row "remove" "apt remove" "Remove package"
    ux_table_row "auto_remove" "apt autoremove" "Remove unused"
    echo ""

    ux_section "Log Viewing"
    ux_table_row "logs" "syslog" "System logs"
    ux_table_row "error" "error.log" "Error logs"
    ux_table_row "auth" "auth.log" "Auth logs"
    echo ""
}

# Alias for sys-help format (using dash instead of underscore)
alias sys-help='sys_help'
