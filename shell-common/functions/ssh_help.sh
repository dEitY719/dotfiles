#!/bin/sh
# shell-common/functions/ssh_help.sh
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

    ux_section "SCP - File Transfer"
    ux_table_row "pull" "scp <host>:<src> <dst>" "Download from server"
    ux_table_row "push" "scp <src> <host>:<dst>" "Upload to server"

    ux_section "Registered Hosts (~/.ssh/config)"
    if [ -f "${HOME}/.ssh/config" ]; then
        set -f  # Disable glob expansion to prevent Host * from expanding
        while IFS= read -r line; do
            # Trim leading whitespace
            line_trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
            case "$line_trimmed" in
                \#* | "")  continue ;;  # Skip comments and empty lines
                Host\ \*)  continue ;;  # Skip wildcard Host *
                Host\ *)
                    hosts="${line_trimmed#Host }"
                    for host in $hosts; do
                        ux_bullet "$host"
                    done
                    ;;
            esac
        done < "${HOME}/.ssh/config"
        set +f  # Re-enable glob expansion
    else
        ux_info "~/.ssh/config not found. Run ./setup.sh to create symlink."
    fi

    ux_section "Config"
    ux_table_row "config file" "~/.ssh/config → dotfiles/ssh/config" "Managed by dotfiles"
}

alias ssh-help='ssh_help'
