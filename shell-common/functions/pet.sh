#!/bin/sh
# shell-common/functions/pet.sh
# pet helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# pet Help and Documentation
# ═══════════════════════════════════════════════════════════════

# Display pet help and usage
pet-help() {
    ux_header "pet - Simple Command Snippet Manager"

    ux_section "Core Concept"
    ux_bullet "Store and recall frequently used commands"
    ux_bullet "Interactive search and execution"
    ux_bullet "Snippets stored as TOML configuration"
    ux_bullet "Built-in editor support for managing snippets"
    ux_bullet "Integrates with shell for easy access"
    echo ""

    ux_section "Core Commands"
    ux_table_row "pet new" "Create a new snippet interactively"
    ux_table_row "pet search" "Search and execute snippet"
    ux_table_row "pet list" "List all stored snippets"
    ux_table_row "pet edit" "Edit snippets in text editor"
    ux_table_row "pet version" "Show pet version"
    echo ""

    ux_section "Snippet Structure"
    ux_info "Each snippet contains:"
    ux_bullet "description - What the snippet does"
    ux_bullet "command - The actual command to execute"
    ux_bullet "tags - Keywords for searching (optional)"
    echo ""

    ux_section "Creating Snippets"
    ux_info "Interactive creation:"
    ux_bullet "pet new - Opens editor to create snippet"
    ux_bullet "Prompts for: description, command, tags"
    ux_bullet "Example: 'Find large files' -> 'find . -size +100M'"
    echo ""

    ux_section "Searching Snippets"
    ux_table_row "pet search" "Interactive search (fzf integration)"
    ux_table_row "pet search 'find'" "Search by description/command"
    ux_table_row "pet list | grep 'find'" "Grep search results"
    echo ""

    ux_section "Snippet Examples"
    echo ""
    ux_info "File Operations:"
    ux_bullet "find large files: find . -size +100M"
    ux_bullet "recursive search: grep -r 'pattern' ."
    ux_bullet "count lines: find . -name '*.rs' | xargs wc -l"
    echo ""

    ux_info "Git Operations:"
    ux_bullet "undo last commit: git reset --soft HEAD~1"
    ux_bullet "delete local branch: git branch -d branch_name"
    ux_bullet "prune remote branches: git remote prune origin"
    echo ""

    ux_info "Docker Operations:"
    ux_bullet "remove dangling images: docker rmi \$(docker images -f dangling=true -q)"
    ux_bullet "clean all: docker system prune -a"
    ux_bullet "view logs: docker logs --follow container_name"
    echo ""

    ux_info "System Commands:"
    ux_bullet "disk usage: du -sh * | sort -h"
    ux_bullet "find and delete: find . -name '.DS_Store' -delete"
    ux_bullet "monitor processes: watch -n 1 'ps aux | grep pattern'"
    echo ""

    ux_section "Using with fzf"
    ux_bullet "pet integrates with fzf for interactive search"
    ux_bullet "Fuzzy match snippets by description or command"
    ux_bullet "Preview snippet before execution"
    ux_bullet "Execute directly from search results"
    echo ""

    ux_section "Configuration File"
    ux_info "Location: ~/.config/pet/config.toml"
    ux_info "Editor integration:"
    ux_bullet "editor = 'vim' - Set preferred editor"
    ux_bullet "selector = 'fzf' - Use fzf for selection"
    ux_bullet "pager = 'less' - Set pager for output"
    echo ""

    ux_section "Snippets Storage"
    ux_info "Location: ~/.config/pet/snippets.toml"
    ux_bullet "Text format (TOML) - easy to edit manually"
    ux_bullet "Portable - copy between systems"
    ux_bullet "Versionable - track with git"
    echo ""

    ux_section "Workflow Examples"
    echo ""
    ux_info "Regular workflow:"
    ux_bullet "Execute a command frequently: pet new"
    ux_bullet "Need to use it later: pet search"
    ux_bullet "Found a better version: pet edit"
    echo ""

    ux_info "Integration with other tools:"
    ux_bullet "Copy snippet command: pet search | xargs echo"
    ux_bullet "Share snippets: Upload ~/.config/pet/snippets.toml"
    ux_bullet "Backup snippets: cp ~/.config/pet/snippets.toml backup/"
    echo ""

    ux_section "Tips & Tricks"
    ux_bullet "Create aliases for frequently used snippets: alias myfunc='pet search'"
    ux_bullet "Document complex commands as snippets instead of comments"
    ux_bullet "Use tags to organize snippets by category"
    ux_bullet "Combine with fzf for fuzzy search experience"
    ux_bullet "Backup snippets regularly - they're valuable"
    echo ""

    ux_section "Comparison with Other Tools"
    ux_bullet "bash history: Unorganized, easy to lose"
    ux_bullet "pet: Organized, searchable, persistent"
    ux_bullet "Man pages: Complex to read"
    ux_bullet "pet: Simple description + example"
    echo ""

    ux_section "Advantages"
    ux_bullet "Simpler than writing scripts for one-off commands"
    ux_bullet "Better than trying to remember complex commands"
    ux_bullet "Easier than searching through bash history"
    ux_bullet "Portable configuration files"
    ux_bullet "Built-in editor for easy management"
    echo ""

    ux_section "Related Help"
    ux_bullet "Install pet: ${UX_BOLD}install-pet${UX_RESET}"
    ux_bullet "Interactive search: ${UX_BOLD}fzf-help${UX_RESET}"
    ux_bullet "Text search: ${UX_BOLD}ripgrep-help${UX_RESET}"
    ux_bullet "Zsh shell: ${UX_BOLD}zsh-help${UX_RESET}"
    echo ""
}
