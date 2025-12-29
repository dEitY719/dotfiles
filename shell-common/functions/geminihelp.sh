#!/bin/sh
# shell-common/functions/geminihelp.sh
# geminiHelp - shared between bash and zsh

geminihelp() {
    ux_header "Gemini CLI Quick Commands"

    ux_section "Basic Commands"
    ux_table_row "gg" "gcloud gemini" "Base command"
    ux_table_row "gflash" "gemini --model flash" "Use Flash model"
    ux_table_row "gpro" "gemini --model pro" "Use Pro model"
    ux_table_row "gver" "gemini --version" "Check version"
    ux_table_row "ghelp" "gemini --help" "Gemini Help"
    echo ""

    ux_section "Installation & Setup"
    ux_table_row "ginstall" "Install Script" "Install Gemini CLI"
    ux_table_row "guninstall" "Uninstall Script" "Remove Gemini CLI"
    echo ""

    ux_section "Tips"
    ux_bullet "Auth via web login (no API key file needed)"
    ux_bullet "Use 'ghelp' for detailed CLI options"
    echo ""
}
