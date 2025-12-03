#!/bin/bash

# ~/dotfiles/bash/env/bash_settings.bash
# Essential Bash shell settings
# Extracted from default_wsl_bashrc.bash with duplicates removed

# =============================================================================
# Interactive Shell Check
# =============================================================================

# Exit if not running interactively
case $- in
*i*) ;;
*) return ;;
esac

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

    # Note: ls/grep color aliases are defined in bash/alias/core_aliases.bash
    # to avoid duplication
fi

# =============================================================================
# Bash Completion
# =============================================================================

# Enable programmable completion features
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        # shellcheck source=/usr/share/bash-completion/bash_completion
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        # shellcheck source=/etc/bash_completion
        . /etc/bash_completion
    fi
fi
