#!/bin/sh

# Skills Sync Alias
# One-shot skills update: git-clone-skills -> git-pull-skills -> claude/setup.sh -> restore-plugins -> update-plugins -> setup-skills-ssot.sh (#1825, #1903, #2344)
# Output: summary mode by default (one line per step, #2126); full output with
# `skills-sync -v` or SKILLS_SYNC_VERBOSE=1. Preview: `skills-sync --dry-run`.
# One step only: `skills-sync --only <step>` (e.g. restore-check); list: `skills-sync -h`.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

alias skills-sync='${HOME}/dotfiles/scripts/update-skills.sh'
