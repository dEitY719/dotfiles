#!/bin/sh
# shell-common/functions/ssai_scp.sh
# SSAI server file transfer utilities (push/pull via scp)
#
# ═══════════════════════════════════════════════════════════════════════════════
# DEVELOPER NOTES - NAMING CONVENTION (See AGENTS.md:174-178)
# ═══════════════════════════════════════════════════════════════════════════════
# User-facing commands: ssai-dev-pull, ssai-dev-push, ssai-ops-pull, ssai-ops-push
# Internal functions:   ssai_dev_pull(), ssai_dev_push(), ssai_ops_pull(), ssai_ops_push()
# Always use dash-form in help text, examples, and error messages
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# ssai_dev_pull() - Pull files from SSAI dev server
# ═══════════════════════════════════════════════════════════════

ssai_dev_pull() {
    if [ $# -lt 1 ]; then
        ux_error "Usage: ssai-dev-pull <remote_src> [local_dst=.]"
        echo ""
        ux_info "Examples:"
        echo "  ssai-dev-pull /home/devops/certs/server.*"
        echo "  ssai-dev-pull /home/devops/certs/server.* ~/download/"
        return 1
    fi
    local remote_src="$1"
    local local_dst="${2:-.}"
    scp "$SSAI_DEV:$remote_src" "$local_dst"
}

# ═══════════════════════════════════════════════════════════════
# ssai_dev_push() - Push files to SSAI dev server
# ═══════════════════════════════════════════════════════════════

ssai_dev_push() {
    if [ $# -lt 2 ]; then
        ux_error "Usage: ssai-dev-push <local_src> <remote_dst>"
        echo ""
        ux_info "Examples:"
        echo "  ssai-dev-push ~/myfile.txt /home/devops/"
        echo "  ssai-dev-push ./config.yaml /home/devops/configs/"
        return 1
    fi
    local local_src="$1"
    local remote_dst="$2"
    scp "$local_src" "$SSAI_DEV:$remote_dst"
}

# ═══════════════════════════════════════════════════════════════
# ssai_ops_pull() - Pull files from SSAI ops server
# ═══════════════════════════════════════════════════════════════

ssai_ops_pull() {
    if [ $# -lt 1 ]; then
        ux_error "Usage: ssai-ops-pull <remote_src> [local_dst=.]"
        echo ""
        ux_info "Examples:"
        echo "  ssai-ops-pull /home/devops/certs/server.*"
        echo "  ssai-ops-pull /home/devops/certs/server.* ~/download/"
        return 1
    fi
    local remote_src="$1"
    local local_dst="${2:-.}"
    scp "$SSAI_OPS:$remote_src" "$local_dst"
}

# ═══════════════════════════════════════════════════════════════
# ssai_ops_push() - Push files to SSAI ops server
# ═══════════════════════════════════════════════════════════════

ssai_ops_push() {
    if [ $# -lt 2 ]; then
        ux_error "Usage: ssai-ops-push <local_src> <remote_dst>"
        echo ""
        ux_info "Examples:"
        echo "  ssai-ops-push ~/myfile.txt /home/devops/"
        echo "  ssai-ops-push ./config.yaml /home/devops/configs/"
        return 1
    fi
    local local_src="$1"
    local remote_dst="$2"
    scp "$local_src" "$SSAI_OPS:$remote_dst"
}

# ═══════════════════════════════════════════════════════════════
# Aliases
# ═══════════════════════════════════════════════════════════════

alias ssai-dev-pull='ssai_dev_pull'
alias ssai-dev-push='ssai_dev_push'
alias ssai-ops-pull='ssai_ops_pull'
alias ssai-ops-push='ssai_ops_push'
