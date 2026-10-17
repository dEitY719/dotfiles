#!/bin/sh
# moved to lib/claude_plugin_manifest.sh (#2154) -- re-source stub for vendored/legacy callers.
# Reverse interactive guard: an interactive shell never loads this library.
case $- in *i*) return 0 ;; esac
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/lib/claude_plugin_manifest.sh"
