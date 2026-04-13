#!/bin/sh
# shell-common/functions/pet.sh
# pet helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# pet Help and Documentation
# ═══════════════════════════════════════════════════════════════

_pet_help_summary() {
    ux_info "Usage: pet-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "concept: snippet manager | search/exec | TOML"
    ux_bullet_sub "core: pet new | search | list | edit | version"
    ux_bullet_sub "structure: description | command | tags"
    ux_bullet_sub "create: pet new (interactive)"
    ux_bullet_sub "search: pet search | grep"
    ux_bullet_sub "examples: file | git | docker | system"
    ux_bullet_sub "fzf | config | storage | workflow | tips | compare | advantages"
    ux_bullet_sub "related: install-pet | fzf-help | ripgrep-help | zsh-help"
    ux_bullet_sub "details: pet-help <section>  (example: pet-help core)"
}

_pet_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "concept"
    ux_bullet_sub "core"
    ux_bullet_sub "structure"
    ux_bullet_sub "create"
    ux_bullet_sub "search"
    ux_bullet_sub "examples"
    ux_bullet_sub "fzf"
    ux_bullet_sub "config"
    ux_bullet_sub "storage"
    ux_bullet_sub "workflow"
    ux_bullet_sub "tips"
    ux_bullet_sub "compare"
    ux_bullet_sub "advantages"
    ux_bullet_sub "related"
}

_pet_help_rows_concept() {
    ux_bullet "Store and recall frequently used commands"
    ux_bullet "Interactive search and execution"
    ux_bullet "Snippets stored as TOML configuration"
    ux_bullet "Built-in editor support for managing snippets"
    ux_bullet "Integrates with shell for easy access"
}

_pet_help_rows_core() {
    ux_table_row "pet new" "Create a new snippet interactively"
    ux_table_row "pet search" "Search and execute snippet"
    ux_table_row "pet list" "List all stored snippets"
    ux_table_row "pet edit" "Edit snippets in text editor"
    ux_table_row "pet version" "Show pet version"
}

_pet_help_rows_structure() {
    ux_info "Each snippet contains:"
    ux_bullet "description - What the snippet does"
    ux_bullet "command - The actual command to execute"
    ux_bullet "tags - Keywords for searching (optional)"
}

_pet_help_rows_create() {
    ux_info "Interactive creation:"
    ux_bullet "pet new - Opens editor to create snippet"
    ux_bullet "Prompts for: description, command, tags"
    ux_bullet "Example: 'Find large files' -> 'find . -size +100M'"
}

_pet_help_rows_search() {
    ux_table_row "pet search" "Interactive search (fzf integration)"
    ux_table_row "pet search 'find'" "Search by description/command"
    ux_table_row "pet list | grep 'find'" "Grep search results"
}

_pet_help_rows_examples() {
    ux_info "File Operations:"
    ux_bullet "find large files: find . -size +100M"
    ux_bullet "recursive search: grep -r 'pattern' ."
    ux_bullet "count lines: find . -name '*.rs' | xargs wc -l"
    ux_info "Git Operations:"
    ux_bullet "undo last commit: git reset --soft HEAD~1"
    ux_bullet "delete local branch: git branch -d branch_name"
    ux_bullet "prune remote branches: git remote prune origin"
    ux_info "Docker Operations:"
    ux_bullet "remove dangling images: docker rmi \$(docker images -f dangling=true -q)"
    ux_bullet "clean all: docker system prune -a"
    ux_bullet "view logs: docker logs --follow container_name"
    ux_info "System Commands:"
    ux_bullet "disk usage: du -sh * | sort -h"
    ux_bullet "find and delete: find . -name '.DS_Store' -delete"
    ux_bullet "monitor processes: watch -n 1 'ps aux | grep pattern'"
}

_pet_help_rows_fzf() {
    ux_bullet "pet integrates with fzf for interactive search"
    ux_bullet "Fuzzy match snippets by description or command"
    ux_bullet "Preview snippet before execution"
    ux_bullet "Execute directly from search results"
}

_pet_help_rows_config() {
    ux_info "Location: ~/.config/pet/config.toml"
    ux_info "Editor integration:"
    ux_bullet "editor = 'vim' - Set preferred editor"
    ux_bullet "selector = 'fzf' - Use fzf for selection"
    ux_bullet "pager = 'less' - Set pager for output"
}

_pet_help_rows_storage() {
    ux_info "Location: ~/.config/pet/snippets.toml"
    ux_bullet "Text format (TOML) - easy to edit manually"
    ux_bullet "Portable - copy between systems"
    ux_bullet "Versionable - track with git"
}

_pet_help_rows_workflow() {
    ux_info "Regular workflow:"
    ux_bullet "Execute a command frequently: pet new"
    ux_bullet "Need to use it later: pet search"
    ux_bullet "Found a better version: pet edit"
    ux_info "Integration with other tools:"
    ux_bullet "Copy snippet command: pet search | xargs echo"
    ux_bullet "Share snippets: Upload ~/.config/pet/snippets.toml"
    ux_bullet "Backup snippets: cp ~/.config/pet/snippets.toml backup/"
}

_pet_help_rows_tips() {
    ux_bullet "Create aliases for frequently used snippets: alias myfunc='pet search'"
    ux_bullet "Document complex commands as snippets instead of comments"
    ux_bullet "Use tags to organize snippets by category"
    ux_bullet "Combine with fzf for fuzzy search experience"
    ux_bullet "Backup snippets regularly - they're valuable"
}

_pet_help_rows_compare() {
    ux_bullet "bash history: Unorganized, easy to lose"
    ux_bullet "pet: Organized, searchable, persistent"
    ux_bullet "Man pages: Complex to read"
    ux_bullet "pet: Simple description + example"
}

_pet_help_rows_advantages() {
    ux_bullet "Simpler than writing scripts for one-off commands"
    ux_bullet "Better than trying to remember complex commands"
    ux_bullet "Easier than searching through bash history"
    ux_bullet "Portable configuration files"
    ux_bullet "Built-in editor for easy management"
}

_pet_help_rows_related() {
    ux_bullet "Install pet: ${UX_BOLD}install-pet${UX_RESET}"
    ux_bullet "Interactive search: ${UX_BOLD}fzf-help${UX_RESET}"
    ux_bullet "Text search: ${UX_BOLD}ripgrep-help${UX_RESET}"
    ux_bullet "Zsh shell: ${UX_BOLD}zsh-help${UX_RESET}"
}

_pet_help_render_section() {
    ux_section "$1"
    "$2"
}

_pet_help_section_rows() {
    case "$1" in
        concept)            _pet_help_rows_concept ;;
        core|commands|cmds) _pet_help_rows_core ;;
        structure)          _pet_help_rows_structure ;;
        create|new)         _pet_help_rows_create ;;
        search)             _pet_help_rows_search ;;
        examples)           _pet_help_rows_examples ;;
        fzf)                _pet_help_rows_fzf ;;
        config|configuration) _pet_help_rows_config ;;
        storage|snippets)   _pet_help_rows_storage ;;
        workflow)           _pet_help_rows_workflow ;;
        tips)               _pet_help_rows_tips ;;
        compare|comparison) _pet_help_rows_compare ;;
        advantages)         _pet_help_rows_advantages ;;
        related)            _pet_help_rows_related ;;
        *)
            ux_error "Unknown pet-help section: $1"
            ux_info "Try: pet-help --list"
            return 1
            ;;
    esac
}

_pet_help_full() {
    ux_header "pet - Simple Command Snippet Manager"
    _pet_help_render_section "Core Concept" _pet_help_rows_concept
    _pet_help_render_section "Core Commands" _pet_help_rows_core
    _pet_help_render_section "Snippet Structure" _pet_help_rows_structure
    _pet_help_render_section "Creating Snippets" _pet_help_rows_create
    _pet_help_render_section "Searching Snippets" _pet_help_rows_search
    _pet_help_render_section "Snippet Examples" _pet_help_rows_examples
    _pet_help_render_section "Using with fzf" _pet_help_rows_fzf
    _pet_help_render_section "Configuration File" _pet_help_rows_config
    _pet_help_render_section "Snippets Storage" _pet_help_rows_storage
    _pet_help_render_section "Workflow Examples" _pet_help_rows_workflow
    _pet_help_render_section "Tips & Tricks" _pet_help_rows_tips
    _pet_help_render_section "Comparison with Other Tools" _pet_help_rows_compare
    _pet_help_render_section "Advantages" _pet_help_rows_advantages
    _pet_help_render_section "Related Help" _pet_help_rows_related
}

pet_help() {
    case "${1:-}" in
        ""|-h|--help|help) _pet_help_summary ;;
        --list|list)        _pet_help_list_sections ;;
        --all|all)          _pet_help_full ;;
        *)                  _pet_help_section_rows "$1" ;;
    esac
}

# Naming Convention: Support both dash and underscore
alias pet-help='pet_help'
