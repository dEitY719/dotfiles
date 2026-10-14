#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/ai_setup.sh
# One-command AI workspace orchestrator.
#
# Creates multiple git worktrees and sets up tmux sessions with
# 3-pane windows for each. Run from the main repo directory.
#
# Usage: ai-setup
#
# Thin wrappers (#2195): the logic is the PATH executables
# tools/custom/ai_setup.sh / ai_teardown.sh (~/.local/bin/ai-setup, ai-teardown).

ai_setup() {
    local _exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/ai_setup.sh
    "$_exe" "$@"
}

ai_teardown() {
    local _exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/ai_teardown.sh
    "$_exe" "$@"
}

alias ai-setup='ai_setup'
alias ai-teardown='ai_teardown'
