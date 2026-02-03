#!/bin/sh
# shell-common/aliases/directory.sh
# Shared directory navigation aliases for bash and zsh

# BASIC
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

# Windows directory paths (WSL)
alias cd-wdocu='cd /mnt/c/Users/bwyoon/Documents'
alias cd-wobsidian='cd /mnt/c/Users/bwyoon/Documents/.obsidian'
alias cd-wdown='cd /mnt/c/Users/bwyoon/Downloads'
alias cd-wpicture='cd /mnt/c/Users/bwyoon/Pictures'
alias cd-tilnote='cd /mnt/c/Users/bwyoon/Documents/ObsidianVault-TilNote'
alias cd-obsidian='cd /mnt/c/Users/bwyoon/Documents/ObsidianVault-TilNote'

# PARA structure
alias mk-para='mkdir -p para/{archive,area,project,resource}'
alias cd-para='cd ~/para'

# PARA directories
alias cd-proj='cd ~/para/project'
alias cd-area='cd ~/para/area'
alias cd-resource='cd ~/para/resource'
alias cd-archive='cd ~/para/archive'

# PROJECT directories
alias cd-rca='cd ~/para/archive/playbook'
alias cd-til='cd ~/para/archive/til'

# Symlink management
alias symlink-manager='${HOME}/dotfiles/bash/app/symlink-manager.sh'
alias symlink-init='${HOME}/dotfiles/bash/app/symlink-manager.sh init'
alias symlink-check='${HOME}/dotfiles/bash/app/symlink-manager.sh check'
alias symlink-config='${HOME}/dotfiles/bash/app/symlink-manager.sh config'
