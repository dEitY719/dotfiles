#!/bin/sh
# shell-common/functions/npmhelp.sh
# npmHelp - shared between bash and zsh

npm_help() {
    ux_header "NPM Quick Commands"

    ux_section "Info & Version"
    ux_table_row "npm-v" "npm --version" "Check version"
    ux_table_row "npm-list" "list -g --depth=0" "Global packages"
    ux_table_row "npm-info" "info <pkg>" "Package details"
    ux_table_row "npm-search" "search <keyword>" "Search packages"
    ux_table_row "npm-outdated" "outdated -g" "Check updates"
    echo ""

    ux_section "Install"
    ux_table_row "npm-i" "npm install" "Install deps"
    ux_table_row "npm-is" "install --save" "Save prod dep"
    ux_table_row "npm-isd" "install --save-dev" "Save dev dep"
    ux_table_row "npm-ig" "install -g" "Global install"
    echo ""

    ux_section "Uninstall"
    ux_table_row "npm-un" "npm uninstall" "Remove dep"
    ux_table_row "npm-ung" "uninstall -g" "Remove global"
    echo ""

    ux_section "Maintenance"
    ux_table_row "npm-update" "update -g" "Update global"
    ux_table_row "npm-cache-clean" "cache clean --force" "Clear cache"
    echo ""

    ux_section "Setup Tools"
    ux_table_row "npminstall" "Install Script" "Install Node/NPM"
    ux_table_row "npmuninstall" "Uninstall Script" "Remove Node/NPM"
    echo ""

    ux_section "Certificate Management"
    ux_info "For CA certificate setup (company proxy/internal network):"
    ux_bullet "Run: ${UX_SUCCESS}crt-help${UX_RESET} for detailed guide"
    ux_bullet "Setup: ${UX_SUCCESS}crtsetup${UX_RESET} to install certificate"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "EACCES permission error (npm WARN): npm config set prefix ~/.npm-global"
    ux_bullet "nvm과 npm prefix 충돌: .npmrc 파일의 prefix 라인 제거"
    ux_bullet "Certificate error: Run ${UX_SUCCESS}crt-help${UX_RESET} for CA setup guide"
    echo ""

    ux_section "Common Commands"
    ux_bullet "npm init"
    ux_bullet "npm run <script>"
    ux_bullet "npm audit fix"
    ux_bullet "npm config list"
    echo ""

    ux_info "Global Path: ~/.npm-global"
}

# Alias for npm-help format (using dash instead of underscore)
alias npm-help='npm_help'
