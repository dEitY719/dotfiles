#!/bin/sh
# shell-common/aliases/directory.sh
# Shared directory navigation aliases for bash and zsh

# BASIC
alias cd_dot='cd "${DOTFILES_ROOT:-$HOME/dotfiles}"'
alias cd_down='cd ~/downloads'
alias cd_work='cd ~/workspace'

# Dotfiles navigation functions
dot() {
    cd "${DOTFILES_ROOT:-$HOME/dotfiles}"
}

dotfiles() {
    cd "${DOTFILES_ROOT:-$HOME/dotfiles}"
}

# Windows directory paths (WSL)
alias cd_wdocu='cd /mnt/c/Users/bwyoon/Documents'
alias cd_wobsidian='cd /mnt/c/Users/bwyoon/Documents/.obsidian'
alias cd_wdown='cd /mnt/c/Users/bwyoon/Downloads'
alias cd_wpicture='cd /mnt/c/Users/bwyoon/Pictures'
alias cd_tilnote='cd /mnt/c/Users/bwyoon/Documents/ObsidianVault-TilNote'
alias cd_obsidian='cd /mnt/c/Users/bwyoon/Documents/ObsidianVault-TilNote'

# PARA structure
alias mkpara='mkdir -p para/{archive,area,project,resource}'
alias cd_para='cd ~/para'

# PARA directories
alias cd_proj='cd ~/para/project'
alias cd_area='cd ~/para/area'
alias cd_resource='cd ~/para/resource'
alias cd_archive='cd ~/para/archive'

# PROJECT directories
alias cd_rca='cd ~/para/archive/rca-knowledge'