#!/bin/zsh

# zsh/app/git.zsh
# Git management commands for zsh
# Note: Zsh has built-in git integration via oh-my-zsh git plugin
# This file provides additional helper functions

# ═══════════════════════════════════════════════════════════════
# Git Help and Information
# ═══════════════════════════════════════════════════════════════

# Display git help and common commands
githelp() {
    ux_header "Git Commands"

    ux_section "Basic Operations"
    ux_table_row "git status" "Show status"
    ux_table_row "git add <file>" "Stage file"
    ux_table_row "git commit -m" "Commit changes"
    ux_table_row "git push" "Push to remote"
    ux_table_row "git pull" "Pull from remote"
    echo ""

    ux_section "Branching"
    ux_table_row "git branch" "List branches"
    ux_table_row "git branch <name>" "Create branch"
    ux_table_row "git checkout <branch>" "Switch branch"
    ux_table_row "git merge <branch>" "Merge branch"
    echo ""

    ux_section "Common Shortcuts (via aliases)"
    ux_table_row "gs" "git status"
    ux_table_row "ga" "git add"
    ux_table_row "gc" "git commit"
    ux_table_row "gp" "git push"
    ux_table_row "gl" "git log"
    ux_table_row "gb" "git branch"
    echo ""

    ux_section "Tips"
    ux_bullet "Use 'git --help' for detailed command documentation"
    ux_bullet "Oh-my-zsh git plugin provides many useful aliases"
    ux_bullet "Use 'git log --oneline' for compact history view"
    ux_bullet "Use 'git diff' to see changes before committing"
    echo ""
}

# Register help function description
# shellcheck disable=SC2034
# Only register if HELP_DESCRIPTIONS exists (loaded by myhelp.zsh)
if [ -n "${HELP_DESCRIPTIONS+x}" ]; then
    HELP_DESCRIPTIONS[githelp]="Git command reference"
fi

# Export functions
export -f githelp
