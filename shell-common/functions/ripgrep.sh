#!/bin/sh
# shell-common/functions/ripgrep.sh
# ripgrep (rg) helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# ripgrep Help and Documentation
# ═══════════════════════════════════════════════════════════════

# Display ripgrep help and usage
ripgrep-help() {
    ux_header "ripgrep (rg) - Fast Text Search Tool"

    ux_section "Core Concept"
    ux_bullet "Rust-based grep replacement - much faster than grep"
    ux_bullet "Respects .gitignore automatically - avoids unwanted files"
    ux_bullet "Automatic parallelization - uses all available CPU cores"
    ux_bullet "Handles binary files gracefully"
    echo ""

    ux_section "Basic Syntax"
    ux_table_row "rg 'pattern'" "Search for pattern in current directory"
    ux_table_row "rg 'pattern' /path" "Search in specific directory"
    ux_table_row "rg 'pattern' file.txt" "Search in specific file"
    echo ""

    ux_section "Case Sensitivity"
    ux_table_row "rg 'pattern'" "Smart case (sensitive if pattern has uppercase)"
    ux_table_row "rg -i 'pattern'" "Case-insensitive search"
    ux_table_row "rg -S 'pattern'" "Case-sensitive (always)"
    echo ""

    ux_section "Pattern Types"
    ux_table_row "rg 'regex'" "Regular expression search (default)"
    ux_table_row "rg -F 'literal'" "Literal string search (no regex)"
    ux_table_row "rg -w 'word'" "Match whole words only"
    ux_table_row "rg -x 'line'" "Match entire lines only"
    echo ""

    ux_section "Output Control"
    ux_table_row "rg -n 'pattern'" "Show line numbers (default)"
    ux_table_row "rg -c 'pattern'" "Count matches per file"
    ux_table_row "rg -l 'pattern'" "List filenames only"
    ux_table_row "rg -o 'pattern'" "Show only matches, not whole lines"
    echo ""

    ux_section "File Filtering"
    ux_table_row "rg 'pattern' -t py" "Search in Python files only"
    ux_table_row "rg 'pattern' -T py" "Exclude Python files"
    ux_table_row "rg 'pattern' --type-list" "Show all available file types"
    ux_table_row "rg 'pattern' -g '*.py'" "Glob pattern filtering"
    echo ""

    ux_section "Scope Control"
    ux_table_row "rg 'pattern'" "Search respecting .gitignore (default)"
    ux_table_row "rg -u 'pattern'" "Skip .gitignore (search hidden/ignored)"
    ux_table_row "rg -uu 'pattern'" "Skip .gitignore and .ignore files"
    ux_table_row "rg -j 1 'pattern'" "Single-threaded search"
    echo ""

    ux_section "Context Display"
    ux_table_row "rg -B 3 'pattern'" "Show 3 lines before match"
    ux_table_row "rg -A 3 'pattern'" "Show 3 lines after match"
    ux_table_row "rg -C 3 'pattern'" "Show 3 lines before and after"
    echo ""

    ux_section "Practical Examples"
    echo ""
    ux_info "Search in specific file type:"
    ux_bullet "rg 'TODO' -t py - Find TODO comments in Python files"
    ux_bullet "rg 'import' -t js src/ - Find imports in JavaScript source"
    echo ""

    ux_info "Search with context:"
    ux_bullet "rg -C 2 'function' - See function definitions with context"
    ux_bullet "rg -B 5 'error' - Show error messages with preceding context"
    echo ""

    ux_info "Counting and statistics:"
    ux_bullet "rg -c 'pattern' | sort -t: -k2 -rn - Count occurrences by file"
    ux_bullet "rg 'pattern' -c --sort=count - Show most frequent matches"
    echo ""

    ux_info "Replace with sed integration:"
    ux_bullet "rg 'old' -l | xargs sed -i 's/old/new/g' - Replace in all matched files"
    ux_bullet "rg 'pattern' --files-with-matches | xargs -I {} sh -c 'echo {}; rg pattern {}'"
    echo ""

    ux_section "Comparison with grep"
    ux_bullet "grep: Standard but slow, easy regex syntax"
    ux_bullet "rg: Much faster (50-100x), auto .gitignore support"
    ux_bullet "rg: Better output formatting, sensible defaults"
    ux_bullet "rg: No need for -r flag for recursion"
    echo ""

    ux_section "Integration with fzf"
    ux_bullet "rg 'pattern' | fzf - Interactive result selection"
    ux_bullet "vim \$(rg -l 'pattern' | fzf) - Open matched file in vim"
    ux_bullet "rg --files | fzf - Find file then search in it"
    echo ""

    ux_section "Configuration File"
    ux_info "Create ~/.ripgreprc for default options:"
    ux_bullet "--color=auto - Always colorize output"
    ux_bullet "--max-columns=200 - Truncate long lines"
    ux_bullet "--smart-case - Smart case sensitivity"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "Not finding files? Use -u to skip .gitignore"
    ux_bullet "Slow search? Use -j 1 to disable parallelization"
    ux_bullet "Too much output? Use -l to list files only, or -c to count"
    echo ""

    ux_section "Related Help"
    ux_bullet "Install ripgrep: ${UX_BOLD}install-ripgrep${UX_RESET}"
    ux_bullet "Fuzzy finder: ${UX_BOLD}fzf-help${UX_RESET}"
    ux_bullet "Fast find: ${UX_BOLD}fd-help${UX_RESET}"
    ux_bullet "File viewer: ${UX_BOLD}bat-help${UX_RESET}"
    echo ""
}
