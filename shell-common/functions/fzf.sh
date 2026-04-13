#!/bin/sh
# shell-common/functions/fzf.sh
# fzf (fuzzy finder) helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# fzf Help and Documentation
# ═══════════════════════════════════════════════════════════════

_fzf_help_summary() {
    ux_info "Usage: fzf-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "core: Ctrl+T | Ctrl+R | Alt+C"
    ux_bullet_sub "nav: Tab | Shift+Tab | Ctrl+K | Ctrl+J | PgUp | PgDn"
    ux_bullet_sub "edit: Ctrl+W | Ctrl+U | Ctrl+A | Ctrl+E | Backspace"
    ux_bullet_sub "select: Ctrl+A | Ctrl+D | Ctrl+X"
    ux_bullet_sub "actions: Enter | Esc | Ctrl+V | Ctrl+L"
    ux_bullet_sub "preview: ? | > | <"
    ux_bullet_sub "examples: file | history | process | git"
    ux_bullet_sub "tips: type | ^ | ! | ' | Tab"
    ux_bullet_sub "config: FZF_DEFAULT_OPTS | FZF_DEFAULT_COMMAND"
    ux_bullet_sub "details: fzf-help <section>  (example: fzf-help core)"
}

_fzf_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "core"
    ux_bullet_sub "nav"
    ux_bullet_sub "edit"
    ux_bullet_sub "select"
    ux_bullet_sub "actions"
    ux_bullet_sub "preview"
    ux_bullet_sub "examples"
    ux_bullet_sub "tips"
    ux_bullet_sub "config"
}

_fzf_help_rows_core() {
    ux_table_row "Ctrl+T" "Insert selected file(s) into command line"
    ux_table_row "Ctrl+R" "Search and insert command from history"
    ux_table_row "Alt+C" "Change to selected directory"
}

_fzf_help_rows_nav() {
    ux_table_row "Tab" "Toggle selection (multi-select mode)"
    ux_table_row "Shift+Tab" "Toggle selection (reverse)"
    ux_table_row "Ctrl+K" "Move cursor up"
    ux_table_row "Ctrl+J" "Move cursor down"
    ux_table_row "Page Up" "Scroll up"
    ux_table_row "Page Down" "Scroll down"
}

_fzf_help_rows_edit() {
    ux_table_row "Ctrl+W" "Delete word backward"
    ux_table_row "Ctrl+U" "Clear line"
    ux_table_row "Ctrl+A" "Move to beginning of line"
    ux_table_row "Ctrl+E" "Move to end of line"
    ux_table_row "Backspace" "Delete character"
}

_fzf_help_rows_select() {
    ux_table_row "Ctrl+A" "Select all items"
    ux_table_row "Ctrl+D" "Deselect all items"
    ux_table_row "Ctrl+X" "Toggle all selections"
}

_fzf_help_rows_actions() {
    ux_table_row "Enter" "Confirm selection(s)"
    ux_table_row "Esc/Ctrl+C" "Abort (no selection)"
    ux_table_row "Ctrl+V" "Toggle preview window"
    ux_table_row "Ctrl+L" "Toggle layout"
}

_fzf_help_rows_preview() {
    ux_table_row "?" "Show/hide help"
    ux_table_row ">" "Toggle info on the right"
    ux_table_row "<" "Toggle info on the left"
}

_fzf_help_rows_examples() {
    ux_info "File selection:"
    ux_bullet "vim \$(fzf) - Open file in vim"
    ux_bullet "cat \$(fzf) - Display file contents"
    ux_bullet "cd \$(dirname \$(fzf)) - Navigate to file's directory"
    ux_info "Command history:"
    ux_bullet "Press Ctrl+R to search command history interactively"
    ux_info "Process selection:"
    ux_bullet "kill -9 \$(pgrep -f process | fzf)"
    ux_info "Git integration:"
    ux_bullet "git checkout \$(git branch | fzf)"
    ux_bullet "git log --oneline | fzf"
}

_fzf_help_rows_tips() {
    ux_bullet "Type to filter: Just start typing to narrow down results"
    ux_bullet "Regex matching: Use ^pattern to match from start"
    ux_bullet "Inverse match: Use !pattern to exclude matches"
    ux_bullet "Exact match: Use 'pattern for exact string match"
    ux_bullet "Multi-select: Use Tab to select multiple items"
}

_fzf_help_rows_config() {
    ux_info "Customize fzf with environment variables:"
    ux_bullet "FZF_DEFAULT_OPTS - Default options"
    ux_bullet "FZF_DEFAULT_COMMAND - Default command"
    ux_bullet "FZF_CTRL_T_COMMAND - Ctrl+T command"
    ux_bullet "FZF_CTRL_R_OPTS - Ctrl+R options"
    ux_bullet "FZF_ALT_C_COMMAND - Alt+C command"
    ux_info "Example: Add to ~/.bashrc or ~/.zshrc"
    ux_bullet "export FZF_DEFAULT_OPTS='--multi --preview \"head -20 {}\"'"
}

_fzf_help_render_section() {
    ux_section "$1"
    "$2"
}

_fzf_help_section_rows() {
    case "$1" in
        core|keys)          _fzf_help_rows_core ;;
        nav|navigation)     _fzf_help_rows_nav ;;
        edit|editing)       _fzf_help_rows_edit ;;
        select|selection)   _fzf_help_rows_select ;;
        actions)            _fzf_help_rows_actions ;;
        preview|display)    _fzf_help_rows_preview ;;
        examples)           _fzf_help_rows_examples ;;
        tips)               _fzf_help_rows_tips ;;
        config|configuration) _fzf_help_rows_config ;;
        *)
            ux_error "Unknown fzf-help section: $1"
            ux_info "Try: fzf-help --list"
            return 1
            ;;
    esac
}

_fzf_help_full() {
    ux_header "fzf - Fuzzy Finder Help"
    _fzf_help_render_section "Core Key Bindings" _fzf_help_rows_core
    _fzf_help_render_section "Selection & Navigation" _fzf_help_rows_nav
    _fzf_help_render_section "Text Editing" _fzf_help_rows_edit
    _fzf_help_render_section "Selection Management" _fzf_help_rows_select
    _fzf_help_render_section "Actions" _fzf_help_rows_actions
    _fzf_help_render_section "Preview & Display" _fzf_help_rows_preview
    _fzf_help_render_section "Examples" _fzf_help_rows_examples
    _fzf_help_render_section "Tips" _fzf_help_rows_tips
    _fzf_help_render_section "Configuration" _fzf_help_rows_config
}

fzf_help() {
    case "${1:-}" in
        ""|-h|--help|help) _fzf_help_summary ;;
        --list|list)        _fzf_help_list_sections ;;
        --all|all)          _fzf_help_full ;;
        *)                  _fzf_help_section_rows "$1" ;;
    esac
}

# Naming Convention: Support both dash and underscore
alias fzf-help='fzf_help'
