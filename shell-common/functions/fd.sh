#!/bin/sh
# shell-common/functions/fd.sh
# fd helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# fd Help and Documentation
# ═══════════════════════════════════════════════════════════════

# Display fd help and usage
fd-help() {
    ux_header "fd - Fast File Finder"

    ux_section "Core Concept"
    ux_bullet "Rust-based find replacement - much faster than find"
    ux_bullet "Respects .gitignore automatically - avoids unwanted files"
    ux_bullet "Smart case sensitivity - case-insensitive unless pattern has uppercase"
    ux_bullet "Intuitive syntax - simpler than find command"
    ux_bullet "Colored output for better readability"
    echo ""

    ux_section "Basic Syntax"
    ux_table_row "fd 'pattern'" "Find files/directories matching pattern"
    ux_table_row "fd 'pattern' /path" "Search in specific directory"
    ux_table_row "fd '^file$'" "Regex pattern search"
    echo ""

    ux_section "Type Filtering"
    ux_table_row "fd -t f 'pattern'" "Find files only"
    ux_table_row "fd -t d 'pattern'" "Find directories only"
    ux_table_row "fd -t l 'pattern'" "Find symlinks only"
    ux_table_row "fd -t x 'pattern'" "Find executable files only"
    echo ""

    ux_section "Case Sensitivity"
    ux_table_row "fd 'pattern'" "Smart case (case-insensitive by default)"
    ux_table_row "fd -s 'pattern'" "Case-sensitive search"
    ux_table_row "fd -i 'pattern'" "Case-insensitive (explicit)"
    echo ""

    ux_section "Extension & File Filtering"
    ux_table_row "fd -e .txt" "Find all .txt files"
    ux_table_row "fd -e .py 'test'" "Find .py files matching pattern"
    ux_table_row "fd -x 'name'" "Find executable files"
    echo ""

    ux_section "Depth Control"
    ux_table_row "fd -d 1 'pattern'" "Search only in current directory"
    ux_table_row "fd -d 2 'pattern'" "Search up to 2 levels deep"
    ux_table_row "fd -d 3 'pattern'" "Search up to 3 levels deep"
    echo ""

    ux_section "Scope & Exclusion"
    ux_table_row "fd 'pattern'" "Respects .gitignore (default)"
    ux_table_row "fd -u 'pattern'" "Skip .gitignore (search ignored files)"
    ux_table_row "fd -H 'pattern'" "Show hidden files/directories"
    ux_table_row "fd --exclude 'dir' 'pattern'" "Exclude specific directory"
    echo ""

    ux_section "Output & Execution"
    ux_table_row "fd -0 'pattern'" "NUL character separator (for xargs)"
    ux_table_row "fd -x CMD 'pattern'" "Execute command for each result"
    ux_table_row "fd -x echo '{}' 'pattern'" "Display full path of matches"
    echo ""

    ux_section "Practical Examples"
    echo ""
    ux_info "Finding specific file types:"
    ux_bullet "fd -e .py - Find all Python files"
    ux_bullet "fd -t f 'test' - Find all test files"
    ux_bullet "fd -t d 'node_modules' - Find all node_modules directories"
    echo ""

    ux_info "Finding without .gitignore:"
    ux_bullet "fd -u '.git' - Find all .git directories (including hidden)"
    ux_bullet "fd -H -t f '.env' - Find .env files (hidden)"
    echo ""

    ux_info "Integration with other tools:"
    ux_bullet "fd -e .rs | xargs wc -l - Count lines in all Rust files"
    ux_bullet "fd -x file {} - Determine file type of all results"
    ux_bullet "fd -x grep 'TODO' {} - Search for TODO in matched files"
    echo ""

    ux_info "Finding within depth limits:"
    ux_bullet "fd -d 1 '.*' - Find all files/dirs in current directory only"
    ux_bullet "fd -d 2 'src' - Find src directories up to 2 levels deep"
    echo ""

    ux_section "Comparison with find"
    ux_bullet "find: Standard but slow, complex syntax"
    ux_bullet "fd: Much faster (10-100x), simpler syntax, auto .gitignore support"
    ux_bullet "find: Full control, can be used in scripts"
    ux_bullet "fd: Better defaults, more intuitive"
    echo ""

    ux_section "Integration with fzf"
    ux_bullet "fd | fzf - Interactive file selection"
    ux_bullet "vim \$(fd -e .txt | fzf) - Open selected file in vim"
    ux_bullet "fd --type f | fzf --preview 'cat {}' - Preview files"
    echo ""

    ux_section "With ripgrep"
    ux_bullet "fd -e .py | xargs rg 'pattern' - Search pattern in Python files"
    ux_bullet "fd -t f | xargs grep -l 'TODO' - Find files with TODO comments"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "Case sensitivity issues? Use smart case or -s/-i flags"
    ux_bullet "Hidden files not showing? Use -H flag"
    ux_bullet "Gitignore being respected? Use -u to override"
    ux_bullet "Command too slow? Try limiting depth with -d flag"
    echo ""

    ux_section "Related Help"
    ux_bullet "Install fd: ${UX_BOLD}install-fd${UX_RESET}"
    ux_bullet "Text search: ${UX_BOLD}ripgrep-help${UX_RESET}"
    ux_bullet "Fuzzy finder: ${UX_BOLD}fzf-help${UX_RESET}"
    ux_bullet "Directory access: ${UX_BOLD}fasd-help${UX_RESET}"
    echo ""
}
