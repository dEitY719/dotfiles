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

# Canonicalize the same way `_dotfiles_setup_mode()` does
# (shell-common/tools/integrations/claude.sh) — legacy numeric values 1/2/3
# from pre-#571 setup.sh map to public/internal/external. Duplicated inline
# rather than sourced: shell-common files carry the interactive guard
# (`case $- in *i*) ;; *) return 0 ;; esac`) that would make sourcing them
# here a no-op, since this hook always runs non-interactively.
_mode_file="$HOME/.dotfiles-setup-mode"
[ -f "$_mode_file" ] || exit 0

_raw=$(tr -d ' \t\n\r' <"$_mode_file" 2>/dev/null)
case "$_raw" in
1 | public) _mode="public" ;;
2 | internal) _mode="internal" ;;
3 | external) _mode="external" ;;
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
