#!/bin/sh

# Skills Sync Alias
# One-shot skills update: git-pull-skills -> claude/setup.sh -> setup-skills-ssot.sh (#1825)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

alias skills-sync='${HOME}/dotfiles/scripts/update-skills.sh'
