#!/bin/sh
# moved to lib/herdr_agent_lookup.sh (#2154) -- re-source stub for vendored/legacy callers.
# Reverse interactive guard: an interactive shell never loads this library.
case $- in *i*) return 0 ;; esac
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/lib/herdr_agent_lookup.sh"
