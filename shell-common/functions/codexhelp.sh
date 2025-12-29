#!/bin/sh
# shell-common/functions/codexhelp.sh
# codexHelp - shared between bash and zsh

codexhelp() {
    ux_header "Codex Quick Commands"

    ux_section "Basic Commands"
    ux_table_row "cx" "codex" "Base command"
    ux_table_row "cxhelp" "codex --help" "Show help"
    ux_table_row "cxver" "codex --version" "Check version"
    echo ""

    ux_section "Installation & Setup"
    ux_table_row "cxinstall" "Install Script" "Install Codex CLI"
    ux_table_row "cxuninstall" "Uninstall Script" "Remove Codex CLI"
    echo ""

    ux_section "Interactive Mode"
    ux_table_row "cx" "codex" "Start interactive"
    ux_table_row "cx prompt" "codex prompt" "Run with prompt"
    echo ""

    ux_section "Tips"
    ux_bullet "Config: ~/.codex/ or ~/.config/codex/"
    ux_bullet "Auth: Use 'cx' to authenticate"
    echo ""
}
