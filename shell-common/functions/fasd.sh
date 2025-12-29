#!/bin/sh
# shell-common/functions/fasd.sh
# fasd (fast access to directories and files) helper functions and documentation
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# fasd Help and Documentation
# ═══════════════════════════════════════════════════════════════

# Display fasd help and usage
fasd-help() {
    ux_header "fasd - Fast Access to Directories and Files"

    ux_section "Core Commands"
    ux_table_row "z <dir>" "Jump to recently used directory"
    ux_table_row "zz <dir>" "Thorough search, jump to directory"
    ux_table_row "f <file>" "Open/edit recently used file"
    ux_table_row "ff <file>" "Thorough search, open file"
    echo ""

    ux_section "Ranking System"
    ux_bullet "Frequency - How often you visit (w weight)"
    ux_bullet "Recency - How recently you visited (time decay)"
    ux_bullet "Combined score determines ranking"
    ux_bullet "Most relevant items appear first"
    echo ""

    ux_section "Pattern Matching"
    ux_table_row "z pro" "Match 'project' (partial)"
    ux_table_row "z my pro" "Match 'my_project' (multiple terms)"
    ux_table_row "z /tmp" "Match full path"
    ux_table_row "z -l" "List directory frecency data"
    echo ""

    ux_section "Advanced Usage"
    ux_table_row "z -r <dir>" "Interactive ranking (by recency)"
    ux_table_row "z -t <dir>" "Interactive ranking (by frequency)"
    ux_table_row "z -e <dir>" "Echo directory path without jumping"
    ux_table_row "z -d <dir>" "Delete frecency data for directory"
    echo ""

    ux_section "Common Use Cases"
    echo ""
    ux_info "Quick directory jumping:"
    ux_bullet "z docs - Jump to most recent 'docs' directory"
    ux_bullet "z project - Navigate to project directory"
    ux_bullet "z dev src - Jump to 'dev/src' or 'src/dev'"
    echo ""

    ux_info "File operations:"
    ux_bullet "vim \$(f project) - Edit file from project directory"
    ux_bullet "cat \$(f config) - View config file"
    ux_bullet "ls \$(zz search) - List files in search directory"
    echo ""

    ux_info "Directory operations:"
    ux_bullet "cd \$(z downloads) && ls - Navigate and list files"
    ux_bullet "z -e config > path.txt - Save directory path to file"
    ux_bullet "cp file.txt \$(z backup)/ - Copy to backup directory"
    echo ""

    ux_section "Tips & Tricks"
    ux_bullet "No exact match needed: 'z pj' may match 'project'"
    ux_bullet "Multiple patterns: 'z my config' for more specificity"
    ux_bullet "View all matches: 'z -l' to see frecency database"
    ux_bullet "Clean history: 'z -d /old/path' to remove from database"
    ux_bullet "Combine with pipes: 'z config | xargs grep pattern'"
    echo ""

    ux_section "Comparison with cd"
    ux_bullet "cd - Requires full/exact path"
    ux_bullet "z - Requires only partial, fuzzy matching"
    ux_bullet "fasd learns from usage patterns over time"
    ux_bullet "No need to remember exact directory structure"
    echo ""

    ux_section "Integration with Other Tools"
    ux_info "Works well with:"
    ux_bullet "fzf - Combine for interactive selection: z -i"
    ux_bullet "vim/neovim - Quick file access: :e \$(f pattern)"
    ux_bullet "grep - Search in recent directories: grep -r pattern \$(z proj)"
    ux_bullet "git - Navigate git repos: z my_repo && git status"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "Not jumping? 'z -l' to verify directory is recorded"
    ux_bullet "Wrong directory? Use more specific patterns"
    ux_bullet "Reset history: Remove ~/.local/share/fasd/data"
    ux_bullet "Verify installation: 'fasd --version'"
    echo ""

    ux_section "Related Help"
    ux_bullet "Install fasd: ${UX_BOLD}install-fasd${UX_RESET}"
    ux_bullet "Fuzzy finder: ${UX_BOLD}fzf-help${UX_RESET}"
    ux_bullet "File manager: ${UX_BOLD}z -i${UX_RESET} (interactive mode)"
    echo ""
}
