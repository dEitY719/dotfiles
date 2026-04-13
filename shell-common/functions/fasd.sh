#!/bin/sh
# shell-common/functions/fasd.sh
# fasd (fast access to directories and files) helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# fasd Help and Documentation
# ═══════════════════════════════════════════════════════════════

_fasd_help_summary() {
    ux_info "Usage: fasd-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "core: z | zz | f | ff"
    ux_bullet_sub "ranking: frequency | recency | combined"
    ux_bullet_sub "patterns: z pro | z my pro | z /tmp | z -l"
    ux_bullet_sub "advanced: -r | -t | -e | -d"
    ux_bullet_sub "usecases: jump dirs | file ops | dir ops"
    ux_bullet_sub "tips: partial match | multiple terms | -l | -d"
    ux_bullet_sub "compare: cd vs z"
    ux_bullet_sub "integration: fzf | vim | grep | git"
    ux_bullet_sub "trouble: -l verify | reset history"
    ux_bullet_sub "related: install-fasd | fzf-help"
    ux_bullet_sub "details: fasd-help <section>  (example: fasd-help core)"
}

_fasd_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "core"
    ux_bullet_sub "ranking"
    ux_bullet_sub "patterns"
    ux_bullet_sub "advanced"
    ux_bullet_sub "usecases"
    ux_bullet_sub "tips"
    ux_bullet_sub "compare"
    ux_bullet_sub "integration"
    ux_bullet_sub "trouble"
    ux_bullet_sub "related"
}

_fasd_help_rows_core() {
    ux_table_row "z <dir>" "Jump to recently used directory"
    ux_table_row "zz <dir>" "Thorough search, jump to directory"
    ux_table_row "f <file>" "Open/edit recently used file"
    ux_table_row "ff <file>" "Thorough search, open file"
}

_fasd_help_rows_ranking() {
    ux_bullet "Frequency - How often you visit (w weight)"
    ux_bullet "Recency - How recently you visited (time decay)"
    ux_bullet "Combined score determines ranking"
    ux_bullet "Most relevant items appear first"
}

_fasd_help_rows_patterns() {
    ux_table_row "z pro" "Match 'project' (partial)"
    ux_table_row "z my pro" "Match 'my_project' (multiple terms)"
    ux_table_row "z /tmp" "Match full path"
    ux_table_row "z -l" "List directory frecency data"
}

_fasd_help_rows_advanced() {
    ux_table_row "z -r <dir>" "Interactive ranking (by recency)"
    ux_table_row "z -t <dir>" "Interactive ranking (by frequency)"
    ux_table_row "z -e <dir>" "Echo directory path without jumping"
    ux_table_row "z -d <dir>" "Delete frecency data for directory"
}

_fasd_help_rows_usecases() {
    ux_info "Quick directory jumping:"
    ux_bullet "z docs - Jump to most recent 'docs' directory"
    ux_bullet "z project - Navigate to project directory"
    ux_bullet "z dev src - Jump to 'dev/src' or 'src/dev'"
    ux_info "File operations:"
    ux_bullet "vim \$(f project) - Edit file from project directory"
    ux_bullet "cat \$(f config) - View config file"
    ux_bullet "ls \$(zz search) - List files in search directory"
    ux_info "Directory operations:"
    ux_bullet "cd \$(z downloads) && ls - Navigate and list files"
    ux_bullet "z -e config > path.txt - Save directory path to file"
    ux_bullet "cp file.txt \$(z backup)/ - Copy to backup directory"
}

_fasd_help_rows_tips() {
    ux_bullet "No exact match needed: 'z pj' may match 'project'"
    ux_bullet "Multiple patterns: 'z my config' for more specificity"
    ux_bullet "View all matches: 'z -l' to see frecency database"
    ux_bullet "Clean history: 'z -d /old/path' to remove from database"
    ux_bullet "Combine with pipes: 'z config | xargs grep pattern'"
}

_fasd_help_rows_compare() {
    ux_bullet "cd - Requires full/exact path"
    ux_bullet "z - Requires only partial, fuzzy matching"
    ux_bullet "fasd learns from usage patterns over time"
    ux_bullet "No need to remember exact directory structure"
}

_fasd_help_rows_integration() {
    ux_info "Works well with:"
    ux_bullet "fzf - Combine for interactive selection: z -i"
    ux_bullet "vim/neovim - Quick file access: :e \$(f pattern)"
    ux_bullet "grep - Search in recent directories: grep -r pattern \$(z proj)"
    ux_bullet "git - Navigate git repos: z my_repo && git status"
}

_fasd_help_rows_trouble() {
    ux_bullet "Not jumping? 'z -l' to verify directory is recorded"
    ux_bullet "Wrong directory? Use more specific patterns"
    ux_bullet "Reset history: Remove ~/.local/share/fasd/data"
    ux_bullet "Verify installation: 'fasd --version'"
}

_fasd_help_rows_related() {
    ux_bullet "Install fasd: ${UX_BOLD}install-fasd${UX_RESET}"
    ux_bullet "Fuzzy finder: ${UX_BOLD}fzf-help${UX_RESET}"
    ux_bullet "File manager: ${UX_BOLD}z -i${UX_RESET} (interactive mode)"
}

_fasd_help_render_section() {
    ux_section "$1"
    "$2"
}

_fasd_help_section_rows() {
    case "$1" in
        core|commands)      _fasd_help_rows_core ;;
        ranking)            _fasd_help_rows_ranking ;;
        patterns|pattern)   _fasd_help_rows_patterns ;;
        advanced)           _fasd_help_rows_advanced ;;
        usecases|examples|use-cases) _fasd_help_rows_usecases ;;
        tips)               _fasd_help_rows_tips ;;
        compare|comparison) _fasd_help_rows_compare ;;
        integration|tools)  _fasd_help_rows_integration ;;
        trouble|troubleshooting) _fasd_help_rows_trouble ;;
        related)            _fasd_help_rows_related ;;
        *)
            ux_error "Unknown fasd-help section: $1"
            ux_info "Try: fasd-help --list"
            return 1
            ;;
    esac
}

_fasd_help_full() {
    ux_header "fasd - Fast Access to Directories and Files"
    _fasd_help_render_section "Core Commands" _fasd_help_rows_core
    _fasd_help_render_section "Ranking System" _fasd_help_rows_ranking
    _fasd_help_render_section "Pattern Matching" _fasd_help_rows_patterns
    _fasd_help_render_section "Advanced Usage" _fasd_help_rows_advanced
    _fasd_help_render_section "Common Use Cases" _fasd_help_rows_usecases
    _fasd_help_render_section "Tips & Tricks" _fasd_help_rows_tips
    _fasd_help_render_section "Comparison with cd" _fasd_help_rows_compare
    _fasd_help_render_section "Integration with Other Tools" _fasd_help_rows_integration
    _fasd_help_render_section "Troubleshooting" _fasd_help_rows_trouble
    _fasd_help_render_section "Related Help" _fasd_help_rows_related
}

fasd_help() {
    case "${1:-}" in
        ""|-h|--help|help) _fasd_help_summary ;;
        --list|list|section|sections)        _fasd_help_list_sections ;;
        --all|all)          _fasd_help_full ;;
        *)                  _fasd_help_section_rows "$1" ;;
    esac
}

# Naming Convention: Support both dash and underscore
alias fasd-help='fasd_help'
