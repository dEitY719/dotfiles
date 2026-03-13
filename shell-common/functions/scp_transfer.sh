#!/bin/sh
# shell-common/functions/scp_transfer.sh
# Generic server file transfer utilities (push/pull via scp)
#
# Server name is automatically mapped to a shell variable:
#   ssai-dev  →  SSAI_DEV
#   ssai-ops  →  SSAI_OPS
#   xxx-server  →  XXX_SERVER
#
# To add a new server, just define a variable in work-aliases.sh:
#   NEW_HOST='user@host'
# Then use: scp-pull new-host <src>
#
# ═══════════════════════════════════════════════════════════════════════════════
# DEVELOPER NOTES - NAMING CONVENTION (See AGENTS.md:174-178)
# ═══════════════════════════════════════════════════════════════════════════════
# User-facing commands: pull-file, push-file
# Internal functions:   pull_file(), push_file(), _scp_resolve_host()
# Always use dash-form in help text, examples, and error messages
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# _scp_resolve_host() - Resolve server name to host string
#   ssai-dev → SSAI_DEV → 'bwyoon@12.81.221.129'
# ═══════════════════════════════════════════════════════════════

_scp_resolve_host() {
    local server="$1"
    local var_name
    var_name=$(echo "$server" | tr '[:lower:]-' '[:upper:]_')
    eval "echo \$$var_name"
}

# ═══════════════════════════════════════════════════════════════
# pull_file() - Pull files from a remote server
# Usage: pull-file <server> <remote_src> [local_dst=.]
# ═══════════════════════════════════════════════════════════════

pull_file() {
    if [ $# -lt 2 ]; then
        ux_error "Usage: pull-file <server> <remote_src> [local_dst=.]"
        echo ""
        ux_info "Server name maps to variable: ssai-dev → \$SSAI_DEV"
        echo ""
        ux_info "Examples:"
        echo "  pull-file ssai-dev /home/devops/certs/server.*"
        echo "  pull-file ssai-ops /home/devops/certs/server.* ~/download/"
        return 1
    fi
    local server="$1"
    local remote_src="$2"
    local local_dst="${3:-.}"

    local host
    host=$(_scp_resolve_host "$server")
    if [ -z "$host" ]; then
        local var_name
        var_name=$(echo "$server" | tr '[:lower:]-' '[:upper:]_')
        ux_error "Unknown server: '$server' (\$$var_name is not set)"
        return 1
    fi

    scp "$host:$remote_src" "$local_dst"
}

# ═══════════════════════════════════════════════════════════════
# push_file() - Push files to a remote server
# Usage: push-file <server> <local_src> <remote_dst>
# ═══════════════════════════════════════════════════════════════

push_file() {
    if [ $# -lt 3 ]; then
        ux_error "Usage: push-file <server> <local_src> <remote_dst>"
        echo ""
        ux_info "Server name maps to variable: ssai-dev → \$SSAI_DEV"
        echo ""
        ux_info "Examples:"
        echo "  push-file ssai-dev ~/myfile.txt /home/devops/"
        echo "  push-file ssai-ops ./config.yaml /home/devops/configs/"
        return 1
    fi
    local server="$1"
    local local_src="$2"
    local remote_dst="$3"

    local host
    host=$(_scp_resolve_host "$server")
    if [ -z "$host" ]; then
        local var_name
        var_name=$(echo "$server" | tr '[:lower:]-' '[:upper:]_')
        ux_error "Unknown server: '$server' (\$$var_name is not set)"
        return 1
    fi

    scp "$local_src" "$host:$remote_dst"
}

# ═══════════════════════════════════════════════════════════════
# Aliases
# ═══════════════════════════════════════════════════════════════

alias pull-file='pull_file'
alias push-file='push_file'
