#!/bin/sh
# shell-common/aliases/directory.sh
# Shared directory navigation aliases for bash and zsh

# BASIC

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

alias cd-dot='cd "${DOTFILES_ROOT:-$HOME/dotfiles}"'
alias cd-down='cd ~/downloads'
alias cd-work='cd ~/workspace'

# Dotfiles navigation functions
dot() {
    cd "${DOTFILES_ROOT:-$HOME/dotfiles}"
}

dotfiles() {
    cd "${DOTFILES_ROOT:-$HOME/dotfiles}"
}

# Windows directory paths (WSL) — /mnt/c/Users/... are Windows-side mounts
# with no $HOME equivalent, so the abs-home guard is explicitly allowed here.
alias cd-wdocu='cd /mnt/c/Users/bwyoon/Documents'                          # allow-abs-home
alias cd-wobsidian='cd /mnt/c/Users/bwyoon/Documents/.obsidian'            # allow-abs-home
alias cd-wdown='cd /mnt/c/Users/bwyoon/Downloads'                          # allow-abs-home
alias cd-wpicture='cd /mnt/c/Users/bwyoon/Pictures'                        # allow-abs-home
alias cd-tilnote='cd /mnt/c/Users/bwyoon/Documents/ObsidianVault-TilNote'  # allow-abs-home
alias cd-obsidian='cd /mnt/c/Users/bwyoon/Documents/ObsidianVault-TilNote' # allow-abs-home

# PARA structure
alias mk-para='mkdir -p para/{archive,area,project,resource}'
alias cd-para='cd ~/para'

# PARA directories
alias cd-proj='cd ~/para/project'
alias cd-project='cd ~/para/project'
alias cd-area='cd ~/para/area'
alias cd-resource='cd ~/para/resource'
alias cd-archive='cd ~/para/archive'

# PROJECT directories
alias cd-ss='cd ~/para/project/stock-steward'
alias cd-ll='cd ~/para/project/litellm'
alias cd-jv='cd ~/para/project/jiravis'
alias cd-at='cd ~/para/project/agent-toolbox'
alias cd-af='cd-at'
alias cd-qf='cd ~/para/project/quantfolio'
alias cd-kk='cd ~/para/project/karakeep'
alias cd-jmcp='cd ~/para/project/jira-mcp'
alias cd-jmcp-as='cd ~/para/project/jira-mcp/mcp-atlassian'
alias cd-jmcp-as-ds='cd ~/para/project/jira-mcp/mcp-atlassian-ds'
# Note: Project-specific CLI commands are defined in project-cli-aliases.sh

# AREA directories
alias cd-vault='cd ~/para/area/vault'

# ARCHIVE directories
alias cd-pb='cd ~/para/archive/playbook'
alias cd-til='cd ~/para/archive/til'

# Symlink management
alias symlink-manager='${SHELL_COMMON_ROOT:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/symlink-manager.sh'
alias symlink-init='symlink-manager init'
alias symlink-check='symlink-manager check'
alias symlink-config='symlink-manager config'
