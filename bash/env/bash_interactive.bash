#!/bin/bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# bash/env/bash_interactive.bash
# Essential interactive Bash settings (the Ubuntu default ~/.bashrc block).
# ~/.bashrc is a symlink to bash/main.bash, so nothing else sets these.
# Loaded by the env/*.bash glob in bash/main.bash; ~/.bashrc.local is
# sourced later, so per-PC overrides (e.g. a larger HISTSIZE) still win.

# Exit if not running in bash
[ -n "$BASH" ] || return 0

# =============================================================================
# History Settings
# =============================================================================

# Don't put duplicate lines or lines starting with space in the history
HISTCONTROL=ignoreboth

# Append to the history file, don't overwrite it
shopt -s histappend

# History size limits
HISTSIZE=1000
HISTFILESIZE=2000

# =============================================================================
# Shell Options
# =============================================================================

# Check the window size after each command and update LINES and COLUMNS
shopt -s checkwinsize

# =============================================================================
# Less Configuration
# =============================================================================

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# =============================================================================
# Debian Chroot Support
# =============================================================================

# Set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# =============================================================================
# Directory Colors
# =============================================================================

# Enable color support for ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    if [ -r ~/.dircolors ]; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi

    # Note: color aliases live in shell-common/aliases/core.sh
fi

# =============================================================================
# Bash Completion
# =============================================================================

# Enable programmable completion features. Skip when /etc/bash.bashrc (or a
# previous reload) already loaded it: re-sourcing costs ~100ms per reload.
if ! shopt -oq posix && [ -z "${BASH_COMPLETION_VERSINFO-}" ]; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        # shellcheck source=/usr/share/bash-completion/bash_completion
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        # shellcheck source=/etc/bash_completion
        . /etc/bash_completion
    fi
fi
