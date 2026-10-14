#!/bin/bash
# shell-common/tools/custom/git_ssh_check.sh
# Test GitHub SSH connection and provide diagnostics
#
# PATH executable since #2195 (~/.local/bin/git-ssh-check via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'git-ssh-check'` resolves it.
# functions/git_ssh_check.sh keeps the `git_ssh_check` / `git-ssh-check` names as a thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

_git_ssh_check_help() {
    ux_usage "git-ssh-check" "" "Test the GHES SSH connection (key, agent, ssh -T)"
    ux_bullet "Host: \$DOTFILES_GHES_HOST (set in shell-common/env/internal.local.sh)"
}

git_ssh_check() {
    case "${1-}" in -h | --help | help)
        _git_ssh_check_help
        return 0
        ;;
    esac
    # Load UX library if available
    if [ -n "$SHELL_COMMON" ] && [ -f "$SHELL_COMMON/tools/ux_lib/ux_lib.sh" ]; then
        . "$SHELL_COMMON/tools/ux_lib/ux_lib.sh"
    fi

    ux_header "GitHub SSH Connection Test"
    echo ""

    # 1. Check SSH key
    if [ -f "${HOME}/.ssh/id_ed25519" ]; then
        ux_success "SSH Key found: ${HOME}/.ssh/id_ed25519"
    else
        ux_error "SSH Key not found: ${HOME}/.ssh/id_ed25519"
        ux_info "Generate SSH key: ssh-keygen -t ed25519 -C '$(hostname)'"
        return 1
    fi
    echo ""

    # 2. Check SSH agent
    if [ -n "$SSH_AUTH_SOCK" ]; then
        ux_success "SSH Agent running (PID: ${SSH_AGENT_PID:-unknown})"
    else
        ux_warning "SSH Agent not running"
        ux_info "Start SSH Agent: eval \"\$(ssh-agent -s)\""
        return 1
    fi
    echo ""

    # 3. Check key in agent
    if ssh-add -l 2>/dev/null | grep -q "id_ed25519"; then
        ux_success "SSH Key registered in agent"
    else
        ux_warning "SSH Key not registered in agent"
        ux_info "Register key: ssh-add ${HOME}/.ssh/id_ed25519"
        return 1
    fi
    echo ""

    # 4. Test GitHub SSH connection (host: DOTFILES_GHES_HOST, #1944)
    if [ -z "${DOTFILES_GHES_HOST-}" ]; then
        ux_warning "DOTFILES_GHES_HOST not set — skipping GHES SSH test"
        ux_info "Internal PC: cp shell-common/env/internal.local.example shell-common/env/internal.local.sh"
        return 1
    fi
    ux_info "Testing GitHub SSH connection..."
    if ssh -T "git@${DOTFILES_GHES_HOST}" >/dev/null 2>&1; then
        ux_success "GitHub SSH connection successful"
        echo ""
    else
        ux_error "GitHub SSH connection failed"
        ux_info ""
        ux_info "Troubleshooting steps:"
        ux_bullet "1. Verify public key is registered in GitHub:"
        ux_bullet_sub "Go to: https://${DOTFILES_GHES_HOST}/settings/keys"
        ux_bullet_sub "Your public key: $(cat "${HOME}/.ssh/id_ed25519.pub")"
        ux_bullet "2. Check SSH config:"
        ux_bullet_sub "cat ~/.ssh/config"
        ux_bullet "3. Test SSH manually:"
        ux_bullet_sub "ssh -vvv git@${DOTFILES_GHES_HOST}"
        ux_bullet "4. SSH Setup Guide: git/doc/SSH_SETUP_GUIDE.md"
        echo ""
        return 1
    fi

    ux_success "All SSH checks passed!"
    echo ""
}


if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    git_ssh_check "$@"
fi
