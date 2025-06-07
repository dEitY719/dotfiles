#!/bin/bash



# bash/app/git.bash

alias gpf_dev_server='git push -f origin HEAD:refs/heads/dev-server'



alias git_log='git log --graph --pretty=format:"%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an" --date=short'

alias git_log2='git log --graph --decorate --date=short --abbrev-commit --pretty=oneline'



export PS1="\[\e]0;\u@\h: \w\a\]\[\e[32m\]\u@\h:\[\e[33m\]\w\[\e[36m\]\$(__git_ps1 '(%s)')\[\e[0m\]\$ "