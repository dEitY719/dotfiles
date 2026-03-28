#!/bin/sh
# shell-common/functions/codex_help.sh

codex_help() {
    ux_header "Codex Quick Commands"

    ux_section "Basic Commands"
    ux_table_row "codex" "codex" "Base command"
    ux_table_row "codex-help" "codex --help" "Show help"
    ux_table_row "codex-quick-help" "codex-quick-help" "Show dotfiles codex commands"
    ux_table_row "codex-version" "codex --version" "Check version"
    ux_table_row "codex-yolo" "codex --dangerously-bypass-approvals-and-sandbox" "Bypass guardrails"

    ux_section "Installation & Setup"
    ux_table_row "codex-install" "Install Script" "Install Codex CLI"
    ux_table_row "codex-uninstall" "Uninstall Script" "Remove Codex CLI"
    ux_table_row "codex-status" "Status Check" "Show installation status"
    ux_table_row "codex-skills-sync" "Skills Sync" "Sync skills symlinks"

    ux_section "Interactive Mode"
    ux_table_row "codex" "codex" "Start interactive"
    ux_table_row "codex prompt" "codex prompt" "Run with prompt"

    ux_section "Tips"
    ux_bullet "Config: ~/.codex/ or ~/.config/codex/"
    ux_bullet "Auth: Use 'codex' to authenticate"
}

alias codex-quick-help='codex_help'
