#!/bin/sh
# shell-common/functions/ssh_help.sh
# SSH / SCP usage help with registered host list
#
# ═══════════════════════════════════════════════════════════════════════════════
# DEVELOPER NOTES - NAMING CONVENTION (See AGENTS.md:174-178)
# ═══════════════════════════════════════════════════════════════════════════════
# User-facing command: ssh-help (dash-form)
# Internal function:   ssh_help() (snake_case)
# ═══════════════════════════════════════════════════════════════════════════════

ssh_help() {
    ux_header "SSH / SCP Commands"

    ux_section "SSH - Connect & Run"
    ux_table_row "ssh <host>" "ssh ssai-dev" "Connect to server"
    ux_table_row "ssh <host> <cmd>" "ssh ssai-dev 'ls /home'" "Run remote command"
    echo ""

    ux_section "SCP - File Transfer"
    ux_table_row "pull" "scp <host>:<src> <dst>" "Download from server"
    ux_table_row "push" "scp <src> <host>:<dst>" "Upload to server"
    echo ""
    ux_info "Examples:"
    echo "  scp ssai-dev:/home/devops/certs/server.* ~/download/"
    echo "  scp ./config.yaml ssai-dev:/home/devops/configs/"
    echo "  scp -r ssai-ops:/home/devops/logs/ ./logs/"
    echo ""

    ux_section "Registered Hosts (~/.ssh/config)"
    if [ -f "${HOME}/.ssh/config" ]; then
        while IFS= read -r line; do
            case "$line" in
                Host\ \*) continue ;;
                Host\ *)
                    host="${line#Host }"
                    ux_bullet "$host"
                    ;;
            esac
        done < "${HOME}/.ssh/config"
    else
        ux_info "~/.ssh/config not found. Run ./setup.sh to create symlink."
    fi
    echo ""

    ux_section "Config"
    ux_table_row "config file" "~/.ssh/config → dotfiles/ssh/config" "Managed by dotfiles"
    echo ""
}

alias ssh-help='ssh_help'
