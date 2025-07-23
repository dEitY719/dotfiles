#!/bin/bash
# directory_aliases.bash

# BASIC
alias cd_dot='cd ~/dotfiles'
alias cd_down='cd ~/downloads'
alias cd_work='cd ~/workspace'

cp_wdown() {
    cp /mnt/c/Users/bwyoon/Downloads/"$1" .
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
