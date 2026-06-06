#!/bin/sh
# shell-common/aliases/obsidian_claude.sh
# Dash-form alias for the obsidian_claude() launcher function.
#
# The function lives in shell-common/functions/obsidian_claude.sh; this
# file only exposes the user-facing dash-form name (naming convention).

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

alias obsidian-claude='obsidian_claude'
