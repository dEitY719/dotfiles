#!/bin/sh
# shell-common/functions/bat_help.sh

_bat_help_summary() {
    ux_info "Usage: bat-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "concept: cat replacement | syntax highlighting | git integration"
    ux_bullet_sub "basic: bat file | piped | multiple"
    ux_bullet_sub "lines: -n | -r 5:10 | -r 5: | -r :10"
    ux_bullet_sub "language: -l | --list-languages | --theme | --list-themes"
    ux_bullet_sub "display: --plain | --color | --style"
    ux_bullet_sub "git: shows changes (green/red)"
    ux_bullet_sub "advanced: -A | -t | --tabs | -H"
    ux_bullet_sub "config: ~/.config/bat/config defaults"
    ux_bullet_sub "related: install-bat | ripgrep-help | fd-help | fzf-help"
    ux_bullet_sub "details: bat-help <section>  (example: bat-help basic)"
}

_bat_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "concept"
    ux_bullet_sub "basic"
    ux_bullet_sub "lines"
    ux_bullet_sub "language"
    ux_bullet_sub "display"
    ux_bullet_sub "git"
    ux_bullet_sub "advanced"
    ux_bullet_sub "config"
    ux_bullet_sub "related"
}

_bat_help_rows_concept() {
    ux_bullet "Cat replacement with syntax highlighting"
    ux_bullet "Supports 200+ languages and file formats"
    ux_bullet "Git integration - shows file changes in color"
    ux_bullet "Automatic language detection from filename"
}

_bat_help_rows_basic() {
    ux_table_row "bat file.txt" "View file with syntax highlighting"
    ux_table_row "cat file.txt | bat" "View piped content"
    ux_table_row "bat file.txt file2.txt" "View multiple files"
}

_bat_help_rows_lines() {
    ux_table_row "bat -n file.txt" "Show line numbers"
    ux_table_row "bat -r 5:10 file.txt" "Show lines 5-10"
    ux_table_row "bat -r 5: file.txt" "Show from line 5 to end"
    ux_table_row "bat -r :10 file.txt" "Show first 10 lines"
}

_bat_help_rows_language() {
    ux_table_row "bat -l python file.py" "Specify language explicitly"
    ux_table_row "bat --list-languages" "Show all supported languages"
    ux_table_row "bat --theme Monokai file.txt" "Use different color theme"
    ux_table_row "bat --list-themes" "Show all available themes"
}

_bat_help_rows_display() {
    ux_table_row "bat --plain file.txt" "Plain output (no decorations)"
    ux_table_row "bat --color=never file.txt" "Disable colors"
    ux_table_row "bat --color=always file.txt" "Force colors"
    ux_table_row "bat --style=numbers file.txt" "Show only line numbers"
}

_bat_help_rows_git() {
    ux_table_row "bat file.txt" "Shows git changes (green/red lines)"
}

_bat_help_rows_advanced() {
    ux_table_row "bat -A file.txt" "Show invisible characters"
    ux_table_row "bat -t file.txt" "Show tabs as visual indicators"
    ux_table_row "bat --tabs 4 file.txt" "Set tab width to 4 spaces"
    ux_table_row "bat -H file.txt" "Highlight specific lines"
}

_bat_help_rows_config() {
    ux_info "Create ~/.config/bat/config for default options:"
    ux_bullet "--theme=Monokai Extended - Set default theme"
    ux_bullet "--style=numbers - Always show line numbers"
    ux_bullet "--tabs=4 - Set tab width"
    ux_bullet "--paging=auto - Auto pagination"
}

_bat_help_rows_related() {
    ux_bullet "Install bat: ${UX_BOLD}install-bat${UX_RESET}"
    ux_bullet "Text search: ${UX_BOLD}ripgrep-help${UX_RESET}"
    ux_bullet "File finder: ${UX_BOLD}fd-help${UX_RESET}"
    ux_bullet "Fuzzy finder: ${UX_BOLD}fzf-help${UX_RESET}"
}

_bat_help_render_section() {
    ux_section "$1"
    "$2"
}

_bat_help_section_rows() {
    case "$1" in
        concept)            _bat_help_rows_concept ;;
        basic|syntax)       _bat_help_rows_basic ;;
        lines|line)         _bat_help_rows_lines ;;
        language|lang|theme) _bat_help_rows_language ;;
        display)            _bat_help_rows_display ;;
        git)                _bat_help_rows_git ;;
        advanced)           _bat_help_rows_advanced ;;
        config|configuration) _bat_help_rows_config ;;
        related)            _bat_help_rows_related ;;
        *)
            ux_error "Unknown bat-help section: $1"
            ux_info "Try: bat-help --list"
            return 1
            ;;
    esac
}

_bat_help_full() {
    ux_header "bat - Cat Replacement with Syntax Highlighting"
    _bat_help_render_section "Core Concept" _bat_help_rows_concept
    _bat_help_render_section "Basic Syntax" _bat_help_rows_basic
    _bat_help_render_section "Line Selection" _bat_help_rows_lines
    _bat_help_render_section "Language & Theme" _bat_help_rows_language
    _bat_help_render_section "Display Control" _bat_help_rows_display
    _bat_help_render_section "Git Integration" _bat_help_rows_git
    _bat_help_render_section "Advanced Options" _bat_help_rows_advanced
    _bat_help_render_section "Configuration" _bat_help_rows_config
    _bat_help_render_section "Related Help" _bat_help_rows_related
}

bat_help() {
    case "${1:-}" in
        ""|-h|--help|help) _bat_help_summary ;;
        --list|list|section|sections)        _bat_help_list_sections ;;
        --all|all)          _bat_help_full ;;
        *)                  _bat_help_section_rows "$1" ;;
    esac
}

alias bat-help='bat_help'
