#!/bin/bash
# shell-common/functions/fzf.sh
# fzf (fuzzy finder) helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# fzf Help and Documentation
# ═══════════════════════════════════════════════════════════════

# Display fzf help and key bindings
fzf_help() {
    ux_header "fzf - Fuzzy Finder Help"

    ux_section "Core Key Bindings"
    ux_table_row "Ctrl+T" "Insert selected file(s) into command line"
    ux_table_row "Ctrl+R" "Search and insert command from history"
    ux_table_row "Alt+C" "Change to selected directory"
    echo ""

    ux_section "Selection & Navigation"
    ux_table_row "Tab" "Toggle selection (multi-select mode)"
    ux_table_row "Shift+Tab" "Toggle selection (reverse)"
    ux_table_row "Ctrl+K" "Move cursor up"
    ux_table_row "Ctrl+J" "Move cursor down"
    ux_table_row "Page Up" "Scroll up"
    ux_table_row "Page Down" "Scroll down"
    echo ""

    ux_section "Text Editing"
    ux_table_row "Ctrl+W" "Delete word backward"
    ux_table_row "Ctrl+U" "Clear line"
    ux_table_row "Ctrl+A" "Move to beginning of line"
    ux_table_row "Ctrl+E" "Move to end of line"
    ux_table_row "Backspace" "Delete character"
    echo ""

    ux_section "Selection Management"
    ux_table_row "Ctrl+A" "Select all items"
    ux_table_row "Ctrl+D" "Deselect all items"
    ux_table_row "Ctrl+X" "Toggle all selections"
    echo ""

    ux_section "Actions"
    ux_table_row "Enter" "Confirm selection(s)"
    ux_table_row "Esc/Ctrl+C" "Abort (no selection)"
    ux_table_row "Ctrl+V" "Toggle preview window"
    ux_table_row "Ctrl+L" "Toggle layout"
    echo ""

    ux_section "Preview & Display"
    ux_table_row "?" "Show/hide help"
    ux_table_row ">" "Toggle info on the right"
    ux_table_row "<" "Toggle info on the left"
    echo ""

    ux_section "Examples"
    echo ""
    ux_info "File selection:"
    ux_bullet "vim \$(fzf) - Open file in vim"
    ux_bullet "cat \$(fzf) - Display file contents"
    ux_bullet "cd \$(dirname \$(fzf)) - Navigate to file's directory"
    echo ""

    ux_info "Command history:"
    ux_bullet "Press Ctrl+R to search command history interactively"
    echo ""

    ux_info "Process selection:"
    ux_bullet "kill -9 \$(pgrep -f process | fzf)"
    echo ""

    ux_info "Git integration:"
    ux_bullet "git checkout \$(git branch | fzf)"
    ux_bullet "git log --oneline | fzf"
    echo ""

    ux_section "Tips"
    ux_bullet "Type to filter: Just start typing to narrow down results"
    ux_bullet "Regex matching: Use ^pattern to match from start"
    ux_bullet "Inverse match: Use !pattern to exclude matches"
    ux_bullet "Exact match: Use 'pattern for exact string match"
    ux_bullet "Multi-select: Use Tab to select multiple items"
    echo ""

    ux_section "Configuration"
    ux_info "Customize fzf with environment variables:"
    ux_bullet "FZF_DEFAULT_OPTS - Default options"
    ux_bullet "FZF_DEFAULT_COMMAND - Default command"
    ux_bullet "FZF_CTRL_T_COMMAND - Ctrl+T command"
    ux_bullet "FZF_CTRL_R_OPTS - Ctrl+R options"
    ux_bullet "FZF_ALT_C_COMMAND - Alt+C command"
    echo ""

    ux_info "Example: Add to ~/.bashrc or ~/.zshrc"
    echo "  export FZF_DEFAULT_OPTS='--multi --preview \"head -20 {}\"'"
    echo ""
}

# Naming Convention: Support both dash and underscore
alias fzf-help='fzf_help'
