#!/bin/bash
# directory_aliases.bash

# BASIC
alias cd_dot='cd ~/dotfiles'
alias cd_down='cd ~/downloads'
alias cd_work='cd ~/workspace'

cp_wdown() {
    if [ -z "$1" ]; then
        echo "Usage: cp_wdown <file1> [file2] ..."
        return 1
    fi
    for file in "$@"; do
        cp "/mnt/c/Users/bwyoon/Downloads/$file" .
    done
}
# window directory
alias cd_wdocu='cd /mnt/c/Users/bwyoon/Documents'
alias cd_wobsidian='cd /mnt/c/Users/bwyoon/Documents/.obsidian'
alias cd_wdown='cd /mnt/c/Users/bwyoon/Downloads'
alias cd_wpicture='cd /mnt/c/Users/bwyoon/Pictures'

# PARA
alias mkpara='mkdir -p para/{archive,area,project,resource}'
alias cd_para='cd ~/para'
alias cd_project='cd ~/para/project'
alias cd_area='cd ~/para/area'
alias cd_resource='cd ~/para/resource'
alias cd_archive='cd ~/para/archive'
