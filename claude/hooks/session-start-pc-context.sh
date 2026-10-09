#!/usr/bin/env bash
# claude/hooks/session-start-pc-context.sh
# Claude Code SessionStart hook: injects the current PC's setup-mode
# (~/.dotfiles-setup-mode) + hostname into the session as additionalContext.
#
# Why: `~/.dotfiles-setup-mode` differs per machine (public/internal/external)
# but nothing told a fresh session which mode the current PC is in —
# CLAUDE.md is shared across all 5 PCs and can't hold a per-machine fact,
# and relying on Claude Code memory to "remember to check" is fragile
# (breaks silently the moment a session skips the check). This hook makes
# the mode injection unconditional and mechanical instead.
#
# Mode file missing (fresh install, setup.sh not run yet) or unrecognized
# → silently emit no context. Never blocks session start.
#
# Always exits 0 — best-effort context injection, never blocks the session.
#
# Reference: issue #1052.

set -u

# Setup-mode reader SSOT (#1810). Resolved from this hook's real location
# (settings.json registers ~/dotfiles/claude/hooks/..., which may be a symlink
# or a different checkout), then the usual shell-common conventions. The lib
# has no interactive guard, so sourcing it here defines the function. No lib
# or an unrecognized mode → silently no context.
_self=$(readlink -f "$0" 2>/dev/null) || _self="$0"
for _sc in "${_self%/*}/../../shell-common" "${SHELL_COMMON:-}" "${DOTFILES_ROOT:-}/shell-common" "$HOME/dotfiles/shell-common"; do
    if [ -r "$_sc/util/setup_mode_read.sh" ]; then
        # shellcheck disable=SC1091
        . "$_sc/util/setup_mode_read.sh"
        break
    fi
done
command -v _dotfiles_setup_mode >/dev/null 2>&1 || exit 0
_mode=$(_dotfiles_setup_mode)
case "$_mode" in
public | internal | external) ;;
*) exit 0 ;;
esac

_hostname=$(hostname 2>/dev/null || echo "")

_context="Dotfiles PC setup-mode: ${_mode}"
[ -n "$_hostname" ] && _context="${_context} (host: ${_hostname})"
_context="${_context}. Mode drives account routing (claude/AGENTS.md) and git host resolution (shell-common/functions/gh_host.sh)."

if command -v jq >/dev/null 2>&1; then
	jq -n --arg ctx "$_context" \
		'{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
else
	printf '%s\n' "$_context"
fi

exit 0
