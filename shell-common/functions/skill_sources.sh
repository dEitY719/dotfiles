#!/bin/sh
# moved to lib/skill_sources.sh (#2154) -- re-source stub for vendored/legacy callers.
# Reverse guard: only the interactive loader pass skips it (dotfiles_load_all).
case $- in *i*) [ -n "${_DOTFILES_LOADING_FUNCTIONS-}" ] && return 0 ;; esac
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/lib/skill_sources.sh"
