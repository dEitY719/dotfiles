#!/bin/sh
# shell-common/tools/integrations/opencode.sh
# OpenCode CLI - setup, utilities, and workflow helpers
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Installation Instructions
# ═══════════════════════════════════════════════════════════════

# Quick Installation (Interactive)
# Run: install-opencode
#
# This will guide you through:
#   1. Environment selection (home/external/internal)
#   2. Verification of Node.js and npm
#   3. OpenCode installation via: npm i -g opencode-ai
#   4. Environment-specific configuration setup
#
# Requirements:
#   - Node.js 16.x or higher
#   - npm 8.x or higher
#   - bash: this script requires bash features
#
# Shell Compatibility:
#   - Works with bash and zsh
#   - The shebang (#!/bin/bash) ensures proper execution
#
# Reference:
#   - Official: https://opencode.ai/
#   - npm package: https://www.npmjs.com/package/opencode-ai
#
# Configuration Locations:
#   - Home/Default: Uses OpenCode's default configuration
#   - External/Internal: ~/.config/opencode/opencode.json
#
# Environment Details:
#   HOME     - Personal PC, local development, SSL verified
#   EXTERNAL - Public network access, GitHub accessible, LiteLLM enabled
#   INTERNAL - Corporate network, Samsung DS proxy, multiple LLM models

# ═══════════════════════════════════════════════════════════════
# Environment Variables
# ═══════════════════════════════════════════════════════════════

# OpenCode configuration directory
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_FILE:-$OPENCODE_CONFIG_DIR/opencode.json}"

# Note: Aliases are unaliased after being defined below (re-sourcing compatibility)

# ═══════════════════════════════════════════════════════════════
# OpenCode Installation
# ═══════════════════════════════════════════════════════════════

install_opencode() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_opencode.sh"
}

# ═══════════════════════════════════════════════════════════════
# OpenCode Configuration Verification
# ═══════════════════════════════════════════════════════════════

opencode_verify() {
    ux_header "OpenCode Configuration Verification"
    echo ""

    # Check if OpenCode is installed
    ux_section "Installation Status"
    if command -v opencode &>/dev/null; then
        ux_success "OpenCode CLI is installed"
        opencode --version
    else
        ux_error "OpenCode CLI is not installed"
        ux_info "Run 'openinstall' to install it"
        echo ""
        return 1
    fi
    echo ""

    # Check configuration file
    ux_section "Configuration"
    if [ -f "$OPENCODE_CONFIG_FILE" ]; then
        ux_success "Configuration file found: $OPENCODE_CONFIG_FILE"
        echo ""

        # Parse and display configuration
        if command -v jq &>/dev/null; then
            ux_bullet "Provider: $(jq -r '.provider | keys[0]' "$OPENCODE_CONFIG_FILE" 2>/dev/null || echo 'unknown')"

            local provider_name
            provider_name=$(jq -r '.provider.litellm.name // "Unknown"' "$OPENCODE_CONFIG_FILE" 2>/dev/null)
            if [ "$provider_name" != "Unknown" ]; then
                ux_bullet "Name: $provider_name"
            fi

            local base_url
            base_url=$(jq -r '.provider.litellm.options.baseURL // "default"' "$OPENCODE_CONFIG_FILE" 2>/dev/null)
            if [ "$base_url" != "default" ]; then
                ux_bullet "Base URL: $base_url"
            fi

            local model_count
            model_count=$(jq '.provider.litellm.models | length' "$OPENCODE_CONFIG_FILE" 2>/dev/null)
            if [ -n "$model_count" ] && [ "$model_count" -gt 0 ]; then
                ux_bullet "Available Models: $model_count"
                jq -r '.provider.litellm.models | keys[]' "$OPENCODE_CONFIG_FILE" 2>/dev/null | while read -r model; do
                    echo "  - $model"
                done
            fi
        else
            ux_warning "jq not installed - unable to parse configuration details"
            ux_info "For detailed configuration view, get jq via your package manager"
            echo ""
            ux_info "Configuration file contents:"
            cat "$OPENCODE_CONFIG_FILE"
        fi
    else
        ux_info "Using OpenCode default configuration"
        ux_info "Custom config file not found: $OPENCODE_CONFIG_FILE"
    fi
    echo ""

    # Check Node.js and npm
    ux_section "Runtime Environment"
    if command -v node &>/dev/null; then
        ux_success "Node.js: $(node --version)"
    else
        ux_error "Node.js not found"
    fi

    if command -v npm &>/dev/null; then
        ux_success "npm: $(npm --version)"
    else
        ux_error "npm not found"
    fi
    echo ""

    ux_header "✅ Verification Complete"
}

# ═══════════════════════════════════════════════════════════════
# OpenCode Help and Documentation
# ═══════════════════════════════════════════════════════════════

opencode_help() {
    ux_header "OpenCode CLI Reference"
    echo ""

    ux_section "Installation & Setup"
    ux_bullet "${UX_PRIMARY}install-opencode${UX_RESET}             : Interactive OpenCode installer"
    ux_bullet "${UX_PRIMARY}opencode-verify${UX_RESET}              : Verify installation & configuration"
    ux_bullet "${UX_PRIMARY}uninstall-opencode${UX_RESET}           : Remove OpenCode and configuration"
    echo ""

    ux_section "Environments"
    ux_bullet "home                    : Personal PC (local dev, SSL verified)"
    ux_bullet "external                : Public network (GitHub, LiteLLM)"
    ux_bullet "internal                : Corporate (Samsung DS, proxy)"
    echo ""

    ux_section "Configuration"
    ux_bullet "Config directory        : ${UX_INFO}$OPENCODE_CONFIG_DIR${UX_RESET}"
    ux_bullet "Config file             : ${UX_INFO}$OPENCODE_CONFIG_FILE${UX_RESET}"
    ux_bullet "Edit configuration      : ${UX_PRIMARY}${EDITOR:-vim} \"\$OPENCODE_CONFIG_FILE\"${UX_RESET}"
    echo ""

    ux_section "Models (LiteLLM Integration)"
    ux_bullet "Home       : OpenCode defaults"
    ux_bullet "External   : gpt-oss-20b"
    ux_bullet "Internal   : GLM-4.6, gpt-oss-120b, DeepSeek-V3.2"
    echo ""

    ux_section "Usage"
    ux_bullet "${UX_PRIMARY}opencode${UX_RESET}                     : Launch OpenCode interactive CLI"
    ux_bullet "${UX_PRIMARY}opencode --help${UX_RESET}              : Show OpenCode help"
    ux_bullet "${UX_PRIMARY}opencode --version${UX_RESET}           : Show OpenCode version"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "Not installed?          : Run ${UX_PRIMARY}install-opencode${UX_RESET}"
    ux_bullet "PATH issues?            : Run ${UX_PRIMARY}source ~/.bashrc${UX_RESET}"
    ux_bullet "LLM not working?        : Run ${UX_PRIMARY}opencode-verify${UX_RESET}"
    ux_bullet "Want to remove?         : Run ${UX_PRIMARY}uninstall-opencode${UX_RESET}"
    echo ""

    ux_section "Resources"
    ux_bullet "Official Docs           : https://opencode.ai/"
    ux_bullet "GitHub Repository       : https://github.com/opencode-ai/opencode"
    ux_bullet "Local Help              : ${UX_PRIMARY}opencode-help${UX_RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# OpenCode Edit Configuration
# ═══════════════════════════════════════════════════════════════

opencode_edit() {
    local config_file="$OPENCODE_CONFIG_FILE"

    if [ ! -f "$config_file" ]; then
        ux_error "Configuration file not found: $config_file"
        ux_info "Run 'openinstall' to create it"
        return 1
    fi

    ux_header "Editing OpenCode Configuration"
    ux_info "File: $config_file"
    echo ""

    ${EDITOR:-vim} "$config_file"

    echo ""
    ux_success "Configuration file edited"
    ux_info "Changes will take effect immediately"
}

# ═══════════════════════════════════════════════════════════════
# OpenCode Workflow Aliases
# ═══════════════════════════════════════════════════════════════

# Main interactive mode (recommended for planning)
alias openplan='opencode'

# Test writing mode
opentest() {
    if [ -z "$1" ]; then
        ux_header "opentest"
        ux_usage "opentest" "\"request\"" "Run OpenCode for test writing"
        ux_bullet "Example: ${UX_INFO}opentest \"Write authentication tests\"${UX_RESET}"
        return 1
    fi
    opencode -p "$1"
}

# ═══════════════════════════════════════════════════════════════
# OpenCode Uninstallation
# ═══════════════════════════════════════════════════════════════

uninstall_opencode() {
    ux_header "OpenCode CLI Uninstaller"
    echo ""

    # Confirmation
    printf "%sAre you sure you want to uninstall OpenCode? (y/N): %s" "$UX_PRIMARY" "$UX_RESET"
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        ux_info "Uninstall cancelled"
        return 0
    fi
    echo ""

    ux_section "Uninstalling OpenCode..."

    # Remove global npm package
    if command -v npm &>/dev/null; then
        ux_info "Removing OpenCode npm package..."
        npm uninstall -g opencode-ai 2>/dev/null || npm uninstall -g opencode 2>/dev/null || true
        ux_success "OpenCode package removed"
    else
        ux_warning "npm not found - skipping npm uninstall"
    fi
    echo ""

    # Remove configuration directory
    if [ -d "$OPENCODE_CONFIG_DIR" ]; then
        ux_info "Removing configuration directory: $OPENCODE_CONFIG_DIR"
        rm -rf "$OPENCODE_CONFIG_DIR"
        ux_success "Configuration removed"
    else
        ux_info "No configuration directory found"
    fi
    echo ""

    ux_header "✅ OpenCode Uninstallation Complete"
    ux_info "OpenCode has been removed from your system"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# Alias Definitions
# ═══════════════════════════════════════════════════════════════

alias install-opencode='install_opencode'
alias opencode-verify='opencode_verify'
alias opencode-help='opencode_help'
alias opencode-edit='opencode_edit'
alias uninstall-opencode='uninstall_opencode'
alias opencfg='opencode_edit'

# ═══════════════════════════════════════════════════════════════
# Re-sourcing Compatibility (unalias previous definitions)
# ═══════════════════════════════════════════════════════════════

# This ensures that re-sourcing this file doesn't cause alias conflicts
for alias_name in opencode-verify opencode-help opencode-edit uninstall-opencode; do
    unalias "$alias_name" 2>/dev/null || true
done

# Re-define aliases after unaliasing (for zsh re-sourcing compatibility)
alias install-opencode='install_opencode'
alias opencode-verify='opencode_verify'
alias opencode-help='opencode_help'
alias opencode-edit='opencode_edit'
alias uninstall-opencode='uninstall_opencode'
alias opencfg='opencode_edit'

# ═══════════════════════════════════════════════════════════════
# Initialization
# ═══════════════════════════════════════════════════════════════

# Do not auto-run at shell init time
# All functions are available on-demand
