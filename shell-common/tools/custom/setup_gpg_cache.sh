#!/bin/bash

# mytool/setup_gpg_cache.sh
# GPG agent 캐싱 설정 스크립트 (편의성 향상)

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

main() {
    clear
    ux_header "GPG Agent Caching Setup"
    ux_info "This script configures GPG passphrase caching for convenience."

    ux_section "Benefits of Caching"
    ux_bullet "Enter passphrase only once per day"
    ux_bullet "Auto-unlock for git-crypt"
    ux_bullet "Balance between security and convenience"
    echo ""

    ux_section "Setup Process"
    ux_numbered 1 "Check GPG installation"
    ux_numbered 2 "Create ~/.gnupg directory if needed"
    ux_numbered 3 "Configure gpg-agent.conf"
    ux_numbered 4 "Restart GPG agent"
    echo ""

    if ! ux_confirm "Do you want to proceed with the setup?" "y"; then
        ux_warning "Setup cancelled"
        exit 0
    fi

    # ========================================
    # Step 1: Check GPG
    # ========================================
    ux_step "1/4" "Checking GPG installation..."

    if ! command -v gpg &>/dev/null; then
        ux_error "gpg is not installed"
        ux_info "Install with: apt-get install gnupg"
        exit 1
    fi
    ux_success "GPG installed: $(gpg --version | head -n 1)"
    echo ""

    # ========================================
    # Step 2: Create .gnupg directory
    # ========================================
    ux_step "2/4" "Checking ~/.gnupg directory..."

    if [[ -d ~/.gnupg ]]; then
        ux_success "~/.gnupg directory already exists"
    else
        mkdir -p ~/.gnupg
        chmod 700 ~/.gnupg
        ux_success "Created ~/.gnupg directory"
    fi
    echo ""

    # ========================================
    # Step 3: Configure gpg-agent.conf
    # ========================================
    ux_step "3/4" "Configuring gpg-agent.conf..."

    local gpg_agent_conf="$HOME/.gnupg/gpg-agent.conf"
    local cache_ttl=86400  # 24 hours in seconds

    # Check if settings already exist
    if grep -q "default-cache-ttl" "$gpg_agent_conf" 2>/dev/null; then
        ux_warning "Cache settings already exist in gpg-agent.conf"
        ux_section "Current Configuration"
        grep -E "cache-ttl|cache-ttl-ssh" "$gpg_agent_conf" 2>/dev/null || echo "  (none)"
        echo ""

        if ux_confirm "Overwrite existing settings?" "n"; then
            # Remove old cache-ttl settings
            sed -i '/default-cache-ttl/d' "$gpg_agent_conf"
            sed -i '/max-cache-ttl/d' "$gpg_agent_conf"
            ux_info "Removed old cache-ttl settings"
        else
            ux_info "Skipping configuration changes"
            exit 0
        fi
    fi

    # Add new settings
    echo "default-cache-ttl $cache_ttl" >> "$gpg_agent_conf"
    echo "max-cache-ttl $cache_ttl" >> "$gpg_agent_conf"
    ux_success "Configured gpg-agent.conf (24-hour caching)"

    echo ""
    ux_section "Added Configuration"
    ux_bullet "default-cache-ttl $cache_ttl"
    ux_bullet "max-cache-ttl $cache_ttl"
    echo ""

    # ========================================
    # Step 4: Reload GPG agent
    # ========================================
    ux_step "4/4" "Restarting GPG agent..."

    if gpg-connect-agent reloadagent /bye &>/dev/null; then
        ux_success "GPG agent restarted successfully"
    else
        ux_warning "GPG agent restart failed (may need manual restart)"
        ux_info "Manual restart: gpgconf --kill gpg-agent"
    fi
    echo ""

    # ========================================
    # Verify configuration
    # ========================================
    ux_section "Configuration Verification"
    ux_section "gpg-agent.conf contents:"
    cat "$gpg_agent_conf" | sed 's/^/  /'
    echo ""

    # ========================================
    # Completion
    # ========================================
    ux_divider_thick
    ux_success "GPG Agent Caching Setup Complete!"
    echo ""

    ux_section "Next Steps"
    ux_numbered 1 "Use GPG or git-crypt unlock to enter passphrase"
    ux_numbered 2 "Passphrase automatically cached for 24 hours"
    ux_numbered 3 "You will only need to enter it once per day"
    echo ""

    ux_section "How Caching Works"
    ux_bullet "First GPG use: Passphrase required"
    ux_bullet "Within 24 hours: Auto-unlocked (no re-entry needed)"
    ux_bullet "After 24 hours: Passphrase re-entry required"
    echo ""

    ux_section "Cache Management"
    ux_info "Clear cache immediately (expire passphrase):"
    echo "  ${UX_PRIMARY}gpgconf --kill gpg-agent${UX_RESET}"
    echo ""
    ux_info "Verify configuration:"
    echo "  ${UX_PRIMARY}cat ~/.gnupg/gpg-agent.conf${UX_RESET}"
    echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
