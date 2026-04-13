#!/bin/sh
# shell-common/functions/ripgrep.sh
# ripgrep (rg) helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# ripgrep Help and Documentation
# ═══════════════════════════════════════════════════════════════

_ripgrep_help_summary() {
    ux_info "Usage: ripgrep-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "concept: fast | gitignore | parallel | binary-safe"
    ux_bullet_sub "basic: pattern | path | file"
    ux_bullet_sub "case: smart | -i | -S"
    ux_bullet_sub "pattern: regex | -F | -w | -x"
    ux_bullet_sub "output: -n | -c | -l | -o"
    ux_bullet_sub "filter: -t | -T | --type-list | -g"
    ux_bullet_sub "scope: -u | -uu | -j 1"
    ux_bullet_sub "context: -B | -A | -C"
    ux_bullet_sub "examples | compare | fzf | config | trouble | related"
    ux_bullet_sub "details: ripgrep-help <section>  (example: ripgrep-help basic)"
}

_ripgrep_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "concept"
    ux_bullet_sub "basic"
    ux_bullet_sub "case"
    ux_bullet_sub "pattern"
    ux_bullet_sub "output"
    ux_bullet_sub "filter"
    ux_bullet_sub "scope"
    ux_bullet_sub "context"
    ux_bullet_sub "examples"
    ux_bullet_sub "compare"
    ux_bullet_sub "fzf"
    ux_bullet_sub "config"
    ux_bullet_sub "trouble"
    ux_bullet_sub "related"
}

_ripgrep_help_rows_concept() {
    ux_bullet "Rust-based grep replacement - much faster than grep"
    ux_bullet "Respects .gitignore automatically - avoids unwanted files"
    ux_bullet "Automatic parallelization - uses all available CPU cores"
    ux_bullet "Handles binary files gracefully"
}

_ripgrep_help_rows_basic() {
    ux_table_row "rg 'pattern'" "Search for pattern in current directory"
    ux_table_row "rg 'pattern' /path" "Search in specific directory"
    ux_table_row "rg 'pattern' file.txt" "Search in specific file"
}

_ripgrep_help_rows_case() {
    ux_table_row "rg 'pattern'" "Smart case (sensitive if pattern has uppercase)"
    ux_table_row "rg -i 'pattern'" "Case-insensitive search"
    ux_table_row "rg -S 'pattern'" "Case-sensitive (always)"
}

_ripgrep_help_rows_pattern() {
    ux_table_row "rg 'regex'" "Regular expression search (default)"
    ux_table_row "rg -F 'literal'" "Literal string search (no regex)"
    ux_table_row "rg -w 'word'" "Match whole words only"
    ux_table_row "rg -x 'line'" "Match entire lines only"
}

_ripgrep_help_rows_output() {
    ux_table_row "rg -n 'pattern'" "Show line numbers (default)"
    ux_table_row "rg -c 'pattern'" "Count matches per file"
    ux_table_row "rg -l 'pattern'" "List filenames only"
    ux_table_row "rg -o 'pattern'" "Show only matches, not whole lines"
}

_ripgrep_help_rows_filter() {
    ux_table_row "rg 'pattern' -t py" "Search in Python files only"
    ux_table_row "rg 'pattern' -T py" "Exclude Python files"
    ux_table_row "rg 'pattern' --type-list" "Show all available file types"
    ux_table_row "rg 'pattern' -g '*.py'" "Glob pattern filtering"
}

_ripgrep_help_rows_scope() {
    ux_table_row "rg 'pattern'" "Search respecting .gitignore (default)"
    ux_table_row "rg -u 'pattern'" "Skip .gitignore (search hidden/ignored)"
    ux_table_row "rg -uu 'pattern'" "Skip .gitignore and .ignore files"
    ux_table_row "rg -j 1 'pattern'" "Single-threaded search"
}

_ripgrep_help_rows_context() {
    ux_table_row "rg -B 3 'pattern'" "Show 3 lines before match"
    ux_table_row "rg -A 3 'pattern'" "Show 3 lines after match"
    ux_table_row "rg -C 3 'pattern'" "Show 3 lines before and after"
}

_ripgrep_help_rows_examples() {
    ux_info "Search in specific file type:"
    ux_bullet "rg 'TODO' -t py - Find TODO comments in Python files"
    ux_bullet "rg 'import' -t js src/ - Find imports in JavaScript source"
    ux_info "Search with context:"
    ux_bullet "rg -C 2 'function' - See function definitions with context"
    ux_bullet "rg -B 5 'error' - Show error messages with preceding context"
    ux_info "Counting and statistics:"
    ux_bullet "rg -c 'pattern' | sort -t: -k2 -rn - Count occurrences by file"
    ux_bullet "rg 'pattern' -c --sort=count - Show most frequent matches"
    ux_info "Replace with sed integration:"
    ux_bullet "rg 'old' -l | xargs sed -i 's/old/new/g' - Replace in all matched files"
    ux_bullet "rg 'pattern' --files-with-matches | xargs -I {} sh -c 'echo {}; rg pattern {}'"
}

_ripgrep_help_rows_compare() {
    ux_bullet "grep: Standard but slow, easy regex syntax"
    ux_bullet "rg: Much faster (50-100x), auto .gitignore support"
    ux_bullet "rg: Better output formatting, sensible defaults"
    ux_bullet "rg: No need for -r flag for recursion"
}

_ripgrep_help_rows_fzf() {
    ux_bullet "rg 'pattern' | fzf - Interactive result selection"
    ux_bullet "vim \$(rg -l 'pattern' | fzf) - Open matched file in vim"
    ux_bullet "rg --files | fzf - Find file then search in it"
}

_ripgrep_help_rows_config() {
    ux_info "Create ~/.ripgreprc for default options:"
    ux_bullet "--color=auto - Always colorize output"
    ux_bullet "--max-columns=200 - Truncate long lines"
    ux_bullet "--smart-case - Smart case sensitivity"
}

_ripgrep_help_rows_trouble() {
    ux_bullet "Not finding files? Use -u to skip .gitignore"
    ux_bullet "Slow search? Use -j 1 to disable parallelization"
    ux_bullet "Too much output? Use -l to list files only, or -c to count"
}

_ripgrep_help_rows_related() {
    ux_bullet "Install ripgrep: ${UX_BOLD}install-ripgrep${UX_RESET}"
    ux_bullet "Fuzzy finder: ${UX_BOLD}fzf-help${UX_RESET}"
    ux_bullet "Fast find: ${UX_BOLD}fd-help${UX_RESET}"
    ux_bullet "File viewer: ${UX_BOLD}bat-help${UX_RESET}"
}

_ripgrep_help_render_section() {
    ux_section "$1"
    "$2"
}

_ripgrep_help_section_rows() {
    case "$1" in
        concept)            _ripgrep_help_rows_concept ;;
        basic|syntax)       _ripgrep_help_rows_basic ;;
        case|case-sensitivity) _ripgrep_help_rows_case ;;
        pattern|patterns)   _ripgrep_help_rows_pattern ;;
        output)             _ripgrep_help_rows_output ;;
        filter|files)       _ripgrep_help_rows_filter ;;
        scope)              _ripgrep_help_rows_scope ;;
        context)            _ripgrep_help_rows_context ;;
        examples|practical) _ripgrep_help_rows_examples ;;
        compare|comparison) _ripgrep_help_rows_compare ;;
        fzf)                _ripgrep_help_rows_fzf ;;
        config|configuration) _ripgrep_help_rows_config ;;
        trouble|troubleshooting) _ripgrep_help_rows_trouble ;;
        related)            _ripgrep_help_rows_related ;;
        *)
            ux_error "Unknown ripgrep-help section: $1"
            ux_info "Try: ripgrep-help --list"
            return 1
            ;;
    esac
}

_ripgrep_help_full() {
    ux_header "ripgrep (rg) - Fast Text Search Tool"
    _ripgrep_help_render_section "Core Concept" _ripgrep_help_rows_concept
    _ripgrep_help_render_section "Basic Syntax" _ripgrep_help_rows_basic
    _ripgrep_help_render_section "Case Sensitivity" _ripgrep_help_rows_case
    _ripgrep_help_render_section "Pattern Types" _ripgrep_help_rows_pattern
    _ripgrep_help_render_section "Output Control" _ripgrep_help_rows_output
    _ripgrep_help_render_section "File Filtering" _ripgrep_help_rows_filter
    _ripgrep_help_render_section "Scope Control" _ripgrep_help_rows_scope
    _ripgrep_help_render_section "Context Display" _ripgrep_help_rows_context
    _ripgrep_help_render_section "Practical Examples" _ripgrep_help_rows_examples
    _ripgrep_help_render_section "Comparison with grep" _ripgrep_help_rows_compare
    _ripgrep_help_render_section "Integration with fzf" _ripgrep_help_rows_fzf
    _ripgrep_help_render_section "Configuration File" _ripgrep_help_rows_config
    _ripgrep_help_render_section "Troubleshooting" _ripgrep_help_rows_trouble
    _ripgrep_help_render_section "Related Help" _ripgrep_help_rows_related
}

ripgrep_help() {
    case "${1:-}" in
        ""|-h|--help|help) _ripgrep_help_summary ;;
        --list|list|section|sections)        _ripgrep_help_list_sections ;;
        --all|all)          _ripgrep_help_full ;;
        *)                  _ripgrep_help_section_rows "$1" ;;
    esac
}

# Naming Convention: Support both dash and underscore
alias ripgrep-help='ripgrep_help'
