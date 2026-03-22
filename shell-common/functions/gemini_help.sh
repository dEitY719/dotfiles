#!/bin/sh
# shell-common/functions/gemini_help.sh

gemini_help() {
    ux_header "Gemini CLI Quick Commands"

    ux_section "Basic Commands"
    ux_table_row "gg" "gcloud gemini" "Base command"
    ux_table_row "gflash" "gemini --model flash" "Use Flash model"
    ux_table_row "gpro" "gemini --model pro" "Use Pro model"
    ux_table_row "gver" "gemini --version" "Check version"
    ux_table_row "ghelp" "gemini --help" "Gemini Help"

    ux_section "Installation & Setup"
    ux_table_row "ginstall" "Install Script" "Install Gemini CLI"
    ux_table_row "guninstall" "Uninstall Script" "Remove Gemini CLI"

    ux_section "Tips"
    ux_bullet "Auth via web login (no API key file needed)"
    ux_bullet "Use 'ghelp' for detailed CLI options"
}

alias gemini-help='gemini_help'
