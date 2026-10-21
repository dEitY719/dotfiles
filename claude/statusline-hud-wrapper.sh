#!/bin/bash

# statusLine wrapper: existing one-line statusline-command.sh on top, then the
# claude-hud lines below it. Claude Code gives the statusLine command its JSON
# on stdin once, so read it into a variable and feed both renderers.
#
# HUD is skipped when its launcher (installed by /claude-hud:setup) or bun is
# missing, leaving the original one-liner untouched.

input=$(cat)

# Resolve own dir through symlinks (same hop-capped walk as statusline-command.sh).
_self="${BASH_SOURCE[0]}"
_hops=0
while [ -L "$_self" ] && [ "$_hops" -lt 40 ]; do
    _link=$(readlink "$_self")
    case "$_link" in
    /*) _self="$_link" ;;
    *) _self="${_self%/*}/${_link}" ;;
    esac
    _hops=$((_hops + 1))
done
_dir="${_self%/*}"
[ "$_dir" = "$_self" ] && _dir="."

printf '%s' "$input" | "${_dir}/statusline-command.sh"

hud="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/claude-hud/statusline.mjs"
runtime=$(command -v bun 2>/dev/null || command -v node 2>/dev/null)
if [ -r "$hud" ] && [ -n "$runtime" ]; then
    printf '%s' "$input" | "$runtime" --env-file /dev/null "$hud"
fi
