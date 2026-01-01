#!/bin/sh
# shell-common/functions/bat.sh
# bat helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# bat Help and Documentation
# ═══════════════════════════════════════════════════════════════

# Display bat help and usage
bat_help() {
    ux_header "bat - Cat Replacement with Syntax Highlighting"

    ux_section "Core Concept"
    ux_bullet "Cat replacement with syntax highlighting"
    ux_bullet "Supports 200+ languages and file formats"
    ux_bullet "Git integration - shows file changes in color"
    ux_bullet "Line numbers, ranges, and paging support"
    ux_bullet "Automatic language detection from filename"
    echo ""

    ux_section "Basic Syntax"
    ux_table_row "bat file.txt" "View file with syntax highlighting"
    ux_table_row "cat file.txt | bat" "View piped content"
    ux_table_row "bat file.txt file2.txt" "View multiple files"
    ux_table_row "bat - < file.txt" "Read from stdin"
    echo ""

    ux_section "Line Selection"
    ux_table_row "bat -n file.txt" "Show line numbers"
    ux_table_row "bat -r 5:10 file.txt" "Show lines 5-10"
    ux_table_row "bat -r 5: file.txt" "Show from line 5 to end"
    ux_table_row "bat -r :10 file.txt" "Show first 10 lines"
    echo ""

    ux_section "Language & Theme"
    ux_table_row "bat -l python file.py" "Specify language explicitly"
    ux_table_row "bat --list-languages" "Show all supported languages"
    ux_table_row "bat --theme Monokai file.txt" "Use different color theme"
    ux_table_row "bat --list-themes" "Show all available themes"
    echo ""

    ux_section "Display Control"
    ux_table_row "bat --plain file.txt" "Plain output (no decorations)"
    ux_table_row "bat --color=never file.txt" "Disable colors"
    ux_table_row "bat --color=always file.txt" "Force colors"
    ux_table_row "bat --style=numbers file.txt" "Show only line numbers"
    echo ""

    ux_section "Git Integration"
    ux_table_row "bat file.txt" "Shows git changes (green/red lines)"
    ux_bullet "Green lines - added in working directory"
    ux_bullet "Red lines - modified in working directory"
    ux_bullet "Blue lines - deleted in working directory"
    echo ""

    ux_section "Advanced Options"
    ux_table_row "bat -A file.txt" "Show invisible characters"
    ux_table_row "bat -t file.txt" "Show tabs as visual indicators"
    ux_table_row "bat --tabs 4 file.txt" "Set tab width to 4 spaces"
    ux_table_row "bat -H file.txt" "Highlight specific lines"
    echo ""

    ux_section "Practical Examples"
    echo ""
    ux_info "View source code with line numbers:"
    ux_bullet "bat -n src/main.rs - View Rust file with syntax highlighting"
    ux_bullet "bat -n config/app.json - View JSON with colors"
    ux_bullet "bat -n script.sh - View shell script with colors"
    echo ""

    ux_info "View specific sections:"
    ux_bullet "bat -r 1:30 file.txt - View first 30 lines"
    ux_bullet "bat -r 100:150 file.txt - View lines 100-150"
    ux_bullet "bat -r 1:5,10:15 file.txt - View multiple ranges"
    echo ""

    ux_info "Integration with other tools:"
    ux_bullet "find . -name '*.py' | xargs bat - View all Python files"
    ux_bullet "grep 'pattern' file.txt | bat --plain - Highlight grep results"
    ux_bullet "git diff | bat - View git diff with colors"
    echo ""

    ux_info "Alias for common usage:"
    ux_bullet "alias cat='bat' - Replace cat completely"
    ux_bullet "bat --paging=never file.txt - View without paging"
    echo ""

    ux_section "Comparison with cat"
    ux_bullet "cat: Basic output, no formatting"
    ux_bullet "bat: Syntax highlighting, git awareness, better defaults"
    ux_bullet "cat: Available everywhere"
    ux_bullet "bat: Feature-rich, faster for code review"
    echo ""

    ux_section "Color Themes"
    ux_info "Popular themes:"
    ux_bullet "Monokai Extended - Dark theme, vibrant colors"
    ux_bullet "Dracula - Dark theme, popular"
    ux_bullet "GitHub - Light theme, GitHub-style colors"
    ux_bullet "Solarized (dark/light) - Popular color scheme"
    echo ""

    ux_section "Configuration"
    ux_info "Create ~/.config/bat/config for default options:"
    ux_bullet "--theme=Monokai Extended - Set default theme"
    ux_bullet "--style=numbers - Always show line numbers"
    ux_bullet "--tabs=4 - Set tab width"
    ux_bullet "--paging=auto - Auto pagination"
    echo ""

    ux_section "File Format Detection"
    ux_bullet "bat automatically detects language from file extension"
    ux_bullet "Supports .py, .rs, .js, .go, .c, .cpp, .java, etc."
    ux_bullet "Use -l flag to override language detection"
    ux_bullet "Use --list-languages to see all supported languages"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "Not showing colors? Check TERM environment variable"
    ux_bullet "Theme not found? List available: bat --list-themes"
    ux_bullet "Wrong language detected? Use -l to specify language"
    ux_bullet "Git changes not showing? Make sure file is in git repository"
    echo ""

    ux_section "Related Help"
    ux_bullet "Install bat: ${UX_BOLD}install-bat${UX_RESET}"
    ux_bullet "Text search: ${UX_BOLD}ripgrep-help${UX_RESET}"
    ux_bullet "File finder: ${UX_BOLD}fd-help${UX_RESET}"
    ux_bullet "Fuzzy finder: ${UX_BOLD}fzf-help${UX_RESET}"
    echo ""
}

# Naming Convention: Function uses underscore, alias provides dash format
# Users call: bat-help (dash format)
# Function: bat_help (underscore format - POSIX compatible)
alias bat-help='bat_help'
