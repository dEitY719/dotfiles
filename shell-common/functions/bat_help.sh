#!/bin/sh
# shell-common/functions/bat_help.sh

bat_help() {
    ux_header "bat - Cat Replacement with Syntax Highlighting"

    ux_section "Core Concept"
    ux_bullet "Cat replacement with syntax highlighting"
    ux_bullet "Supports 200+ languages and file formats"
    ux_bullet "Git integration - shows file changes in color"
    ux_bullet "Automatic language detection from filename"

    ux_section "Basic Syntax"
    ux_table_row "bat file.txt" "View file with syntax highlighting"
    ux_table_row "cat file.txt | bat" "View piped content"
    ux_table_row "bat file.txt file2.txt" "View multiple files"

    ux_section "Line Selection"
    ux_table_row "bat -n file.txt" "Show line numbers"
    ux_table_row "bat -r 5:10 file.txt" "Show lines 5-10"
    ux_table_row "bat -r 5: file.txt" "Show from line 5 to end"
    ux_table_row "bat -r :10 file.txt" "Show first 10 lines"

    ux_section "Language & Theme"
    ux_table_row "bat -l python file.py" "Specify language explicitly"
    ux_table_row "bat --list-languages" "Show all supported languages"
    ux_table_row "bat --theme Monokai file.txt" "Use different color theme"
    ux_table_row "bat --list-themes" "Show all available themes"

    ux_section "Display Control"
    ux_table_row "bat --plain file.txt" "Plain output (no decorations)"
    ux_table_row "bat --color=never file.txt" "Disable colors"
    ux_table_row "bat --color=always file.txt" "Force colors"
    ux_table_row "bat --style=numbers file.txt" "Show only line numbers"

    ux_section "Git Integration"
    ux_table_row "bat file.txt" "Shows git changes (green/red lines)"

    ux_section "Advanced Options"
    ux_table_row "bat -A file.txt" "Show invisible characters"
    ux_table_row "bat -t file.txt" "Show tabs as visual indicators"
    ux_table_row "bat --tabs 4 file.txt" "Set tab width to 4 spaces"
    ux_table_row "bat -H file.txt" "Highlight specific lines"

    ux_section "Configuration"
    ux_info "Create ~/.config/bat/config for default options:"
    ux_bullet "--theme=Monokai Extended - Set default theme"
    ux_bullet "--style=numbers - Always show line numbers"
    ux_bullet "--tabs=4 - Set tab width"
    ux_bullet "--paging=auto - Auto pagination"

    ux_section "Related Help"
    ux_bullet "Install bat: ${UX_BOLD}install-bat${UX_RESET}"
    ux_bullet "Text search: ${UX_BOLD}ripgrep-help${UX_RESET}"
    ux_bullet "File finder: ${UX_BOLD}fd-help${UX_RESET}"
    ux_bullet "Fuzzy finder: ${UX_BOLD}fzf-help${UX_RESET}"
}

alias bat-help='bat_help'
