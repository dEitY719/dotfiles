#!/bin/sh
# shell-common/functions/git_ssh_check.sh
# Test GitHub SSH connection and provide diagnostics

git_ssh_check() {
    # Load UX library if available
    if [ -n "$SHELL_COMMON" ] && [ -f "$SHELL_COMMON/tools/ux_lib/ux_lib.sh" ]; then
        source "$SHELL_COMMON/tools/ux_lib/ux_lib.sh"
    fi

    ux_header "GitHub SSH Connection Test"
    echo ""

    # 1. Check SSH key
    if [ -f "${HOME}/.ssh/id_ed25519" ]; then
        ux_success "✓ SSH Key found: ${HOME}/.ssh/id_ed25519"
    else
        ux_error "✗ SSH Key not found: ${HOME}/.ssh/id_ed25519"
        ux_info "Generate SSH key: ssh-keygen -t ed25519 -C '$(hostname)'"
        return 1
    fi
    echo ""

    # 2. Check SSH agent
    if [ -n "$SSH_AUTH_SOCK" ]; then
        ux_success "✓ SSH Agent running (PID: ${SSH_AGENT_PID:-unknown})"
    else
        ux_warning "⚠ SSH Agent not running"
        ux_info "Start SSH Agent: eval \"\$(ssh-agent -s)\""
        return 1
    fi
    echo ""

    # 3. Check key in agent
    if ssh-add -l 2>/dev/null | grep -q "id_ed25519"; then
        ux_success "✓ SSH Key registered in agent"
    else
        ux_warning "⚠ SSH Key not registered in agent"
        ux_info "Register key: ssh-add ${HOME}/.ssh/id_ed25519"
        return 1
    fi
    echo ""

    # 4. Test GitHub SSH connection
    ux_info "Testing GitHub SSH connection..."
    if ssh -T git@github.samsungds.net >/dev/null 2>&1; then
        ux_success "✓ GitHub SSH connection successful"
        echo ""
    else
        ux_error "✗ GitHub SSH connection failed"
        ux_info ""
        ux_info "Troubleshooting steps:"
        ux_bullet "1. Verify public key is registered in GitHub:"
        ux_bullet "   - Go to: https://github.samsungds.net/settings/keys"
        ux_bullet "   - Your public key: $(cat ${HOME}/.ssh/id_ed25519.pub)"
        ux_bullet "2. Check SSH config:"
        ux_bullet "   - cat ~/.ssh/config"
        ux_bullet "3. Test SSH manually:"
        ux_bullet "   - ssh -vvv git@github.samsungds.net"
        ux_bullet "4. SSH Setup Guide: git/doc/SSH_SETUP_GUIDE.md"
        echo ""
        return 1
    fi

    ux_success "All SSH checks passed!"
    echo ""
}

# Alias for dash format
alias git-ssh-check='git_ssh_check'
