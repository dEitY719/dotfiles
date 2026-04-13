#!/bin/sh
# shell-common/functions/fd.sh
# fd helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# fd Help and Documentation
# ═══════════════════════════════════════════════════════════════

_fd_help_summary() {
    ux_info "Usage: fd-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "concept: fast | gitignore | smart-case | colored"
    ux_bullet_sub "basic: pattern | path | regex"
    ux_bullet_sub "type: -t f | -t d | -t l | -t x"
    ux_bullet_sub "case: smart | -s | -i"
    ux_bullet_sub "extension: -e | -x"
    ux_bullet_sub "depth: -d 1 | -d 2 | -d 3"
    ux_bullet_sub "scope: -u | -H | --exclude"
    ux_bullet_sub "exec: -0 | -x"
    ux_bullet_sub "examples | compare | fzf | ripgrep | trouble | related"
    ux_bullet_sub "details: fd-help <section>  (example: fd-help basic)"
}

_fd_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "concept"
    ux_bullet_sub "basic"
    ux_bullet_sub "type"
    ux_bullet_sub "case"
    ux_bullet_sub "extension"
    ux_bullet_sub "depth"
    ux_bullet_sub "scope"
    ux_bullet_sub "exec"
    ux_bullet_sub "examples"
    ux_bullet_sub "compare"
    ux_bullet_sub "fzf"
    ux_bullet_sub "ripgrep"
    ux_bullet_sub "trouble"
    ux_bullet_sub "related"
}

_fd_help_rows_concept() {
    ux_bullet "Rust-based find replacement - much faster than find"
    ux_bullet "Respects .gitignore automatically - avoids unwanted files"
    ux_bullet "Smart case sensitivity - case-insensitive unless pattern has uppercase"
    ux_bullet "Intuitive syntax - simpler than find command"
    ux_bullet "Colored output for better readability"
}

_fd_help_rows_basic() {
    ux_table_row "fd 'pattern'" "Find files/directories matching pattern"
    ux_table_row "fd 'pattern' /path" "Search in specific directory"
    ux_table_row "fd '^file$'" "Regex pattern search"
}

_fd_help_rows_type() {
    ux_table_row "fd -t f 'pattern'" "Find files only"
    ux_table_row "fd -t d 'pattern'" "Find directories only"
    ux_table_row "fd -t l 'pattern'" "Find symlinks only"
    ux_table_row "fd -t x 'pattern'" "Find executable files only"
}

_fd_help_rows_case() {
    ux_table_row "fd 'pattern'" "Smart case (case-insensitive by default)"
    ux_table_row "fd -s 'pattern'" "Case-sensitive search"
    ux_table_row "fd -i 'pattern'" "Case-insensitive (explicit)"
}

_fd_help_rows_extension() {
    ux_table_row "fd -e .txt" "Find all .txt files"
    ux_table_row "fd -e .py 'test'" "Find .py files matching pattern"
    ux_table_row "fd -x 'name'" "Find executable files"
}

_fd_help_rows_depth() {
    ux_table_row "fd -d 1 'pattern'" "Search only in current directory"
    ux_table_row "fd -d 2 'pattern'" "Search up to 2 levels deep"
    ux_table_row "fd -d 3 'pattern'" "Search up to 3 levels deep"
}

_fd_help_rows_scope() {
    ux_table_row "fd 'pattern'" "Respects .gitignore (default)"
    ux_table_row "fd -u 'pattern'" "Skip .gitignore (search ignored files)"
    ux_table_row "fd -H 'pattern'" "Show hidden files/directories"
    ux_table_row "fd --exclude 'dir' 'pattern'" "Exclude specific directory"
}

_fd_help_rows_exec() {
    ux_table_row "fd -0 'pattern'" "NUL character separator (for xargs)"
    ux_table_row "fd -x CMD 'pattern'" "Execute command for each result"
    ux_table_row "fd -x echo '{}' 'pattern'" "Display full path of matches"
}

_fd_help_rows_examples() {
    ux_info "Finding specific file types:"
    ux_bullet "fd -e .py - Find all Python files"
    ux_bullet "fd -t f 'test' - Find all test files"
    ux_bullet "fd -t d 'node_modules' - Find all node_modules directories"
    ux_info "Finding without .gitignore:"
    ux_bullet "fd -u '.git' - Find all .git directories (including hidden)"
    ux_bullet "fd -H -t f '.env' - Find .env files (hidden)"
    ux_info "Integration with other tools:"
    ux_bullet "fd -e .rs | xargs wc -l - Count lines in all Rust files"
    ux_bullet "fd -x file {} - Determine file type of all results"
    ux_bullet "fd -x grep 'TODO' {} - Search for TODO in matched files"
    ux_info "Finding within depth limits:"
    ux_bullet "fd -d 1 '.*' - Find all files/dirs in current directory only"
    ux_bullet "fd -d 2 'src' - Find src directories up to 2 levels deep"
}

_fd_help_rows_compare() {
    ux_bullet "find: Standard but slow, complex syntax"
    ux_bullet "fd: Much faster (10-100x), simpler syntax, auto .gitignore support"
    ux_bullet "find: Full control, can be used in scripts"
    ux_bullet "fd: Better defaults, more intuitive"
}

_fd_help_rows_fzf() {
    ux_bullet "fd | fzf - Interactive file selection"
    ux_bullet "vim \$(fd -e .txt | fzf) - Open selected file in vim"
    ux_bullet "fd --type f | fzf --preview 'cat {}' - Preview files"
}

_fd_help_rows_ripgrep() {
    ux_bullet "fd -e .py | xargs rg 'pattern' - Search pattern in Python files"
    ux_bullet "fd -t f | xargs grep -l 'TODO' - Find files with TODO comments"
}

_fd_help_rows_trouble() {
    ux_bullet "Case sensitivity issues? Use smart case or -s/-i flags"
    ux_bullet "Hidden files not showing? Use -H flag"
    ux_bullet "Gitignore being respected? Use -u to override"
    ux_bullet "Command too slow? Try limiting depth with -d flag"
}

_fd_help_rows_related() {
    ux_bullet "Install fd: ${UX_BOLD}install-fd${UX_RESET}"
    ux_bullet "Text search: ${UX_BOLD}ripgrep-help${UX_RESET}"
    ux_bullet "Fuzzy finder: ${UX_BOLD}fzf-help${UX_RESET}"
    ux_bullet "Directory access: ${UX_BOLD}fasd-help${UX_RESET}"
}

_fd_help_render_section() {
    ux_section "$1"
    "$2"
}

_fd_help_section_rows() {
    case "$1" in
        concept)            _fd_help_rows_concept ;;
        basic|syntax)       _fd_help_rows_basic ;;
        type|types)         _fd_help_rows_type ;;
        case|case-sensitivity) _fd_help_rows_case ;;
        extension|ext|filter) _fd_help_rows_extension ;;
        depth)              _fd_help_rows_depth ;;
        scope|exclude)      _fd_help_rows_scope ;;
        exec|output)        _fd_help_rows_exec ;;
        examples|practical) _fd_help_rows_examples ;;
        compare|comparison) _fd_help_rows_compare ;;
        fzf)                _fd_help_rows_fzf ;;
        ripgrep|rg)         _fd_help_rows_ripgrep ;;
        trouble|troubleshooting) _fd_help_rows_trouble ;;
        related)            _fd_help_rows_related ;;
        *)
            ux_error "Unknown fd-help section: $1"
            ux_info "Try: fd-help --list"
            return 1
            ;;
    esac
}

_fd_help_full() {
    ux_header "fd - Fast File Finder"
    _fd_help_render_section "Core Concept" _fd_help_rows_concept
    _fd_help_render_section "Basic Syntax" _fd_help_rows_basic
    _fd_help_render_section "Type Filtering" _fd_help_rows_type
    _fd_help_render_section "Case Sensitivity" _fd_help_rows_case
    _fd_help_render_section "Extension & File Filtering" _fd_help_rows_extension
    _fd_help_render_section "Depth Control" _fd_help_rows_depth
    _fd_help_render_section "Scope & Exclusion" _fd_help_rows_scope
    _fd_help_render_section "Output & Execution" _fd_help_rows_exec
    _fd_help_render_section "Practical Examples" _fd_help_rows_examples
    _fd_help_render_section "Comparison with find" _fd_help_rows_compare
    _fd_help_render_section "Integration with fzf" _fd_help_rows_fzf
    _fd_help_render_section "With ripgrep" _fd_help_rows_ripgrep
    _fd_help_render_section "Troubleshooting" _fd_help_rows_trouble
    _fd_help_render_section "Related Help" _fd_help_rows_related
}

fd_help() {
    case "${1:-}" in
        ""|-h|--help|help) _fd_help_summary ;;
        --list|list)        _fd_help_list_sections ;;
        --all|all)          _fd_help_full ;;
        *)                  _fd_help_section_rows "$1" ;;
    esac
}

# Naming Convention: Support both dash and underscore
alias fd-help='fd_help'
