#!/usr/bin/env bash
# claude/hooks/session-start-settings-drift.sh
#
# Claude Code SessionStart hook: warn when the live ~/.claude*/settings.json
# `.hooks` block has drifted from the dotfiles SSOT (claude/settings.json).
#
# Why (#1086): in every mode the live settings.json is a REAL FILE, not a
# symlink — multi-account copies the SSOT (#940), internal deep-merges
# SSOT + Bedrock overlay (#687). So a commit that adds or changes a hook in
# the SSOT does NOT reach the live file until `./setup.sh` (internal:
# `./aws/setup.sh`) is re-run. A user who only `git pull`s + restarts Claude
# Code starts sessions with the OLD hook set, so new hooks silently never
# fire — the concrete failure mode that hid plugin-sync-session.sh for ~1h.
# This hook makes that drift loud instead of silent.
#
# Compares ONLY the `.hooks` field: the Bedrock overlay touches
# env / model / availableModels but never `.hooks`, so after a re-seed the
# two `.hooks` blocks are byte-identical — any difference means the live file
# is stale (or hand-edited, which also warrants a heads-up).
#
# Inherent limit: this detector can only fire once it is itself present in the
# live file, so it cannot warn about its own first install — but every hook
# added AFTER it is covered, which is the recurring pattern (#1086).
#
# Best-effort: always exits 0, never blocks the session. jq missing, either
# file absent, or malformed JSON → silent no-op.
#
# Reference: issue #1086. Sibling SessionStart hooks:
# session-start-pc-context.sh (#1052), plugin-sync-session.sh (#1082).
set -u

# A hook always receives JSON on stdin; a terminal means it was launched by
# hand — bail before `cat` blocks forever.
[ -t 0 ] && exit 0
input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""') || exit 0
[ "$event" = "SessionStart" ] || exit 0

# SSOT resolves relative to this script (…/claude/hooks/x.sh → …/claude), so a
# non-standard dotfiles checkout path still works. $0 is absolute (the hook is
# registered with an absolute command path), so the literal `..` in the path
# resolves fine for `[ -f ]`/jq without needing cd+pwd. LIVE follows the same
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude} convention as statusline-command.sh.
_hook_dir=$(dirname -- "$0")
SSOT="$_hook_dir/../settings.json"
LIVE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

[ -f "$SSOT" ] || exit 0
[ -f "$LIVE" ] || exit 0

ssot_hooks=$(jq -S -c '.hooks // {}' "$SSOT" 2>/dev/null) || exit 0
live_hooks=$(jq -S -c '.hooks // {}' "$LIVE" 2>/dev/null) || exit 0

[ "$ssot_hooks" = "$live_hooks" ] && exit 0

# --- Drift detected ---
# Point the user at the right re-seed entry point for their mode (internal PC
# seeds via aws/setup.sh's Bedrock merge; everyone else via ./setup.sh).
_reseed="./setup.sh"
if [ -f "$HOME/.dotfiles-setup-mode" ]; then
	_raw=$(tr -d ' \t\n\r' <"$HOME/.dotfiles-setup-mode" 2>/dev/null)
	case "$_raw" in
	2 | internal) _reseed="./aws/setup.sh" ;;
	esac
fi

_msg="[dotfiles #1086] Claude settings.json hook drift: the live config (${LIVE}) .hooks block differs from the dotfiles SSOT (claude/settings.json). New or changed hooks will NOT fire until you re-seed the live file — run ${_reseed} in your dotfiles checkout, then restart Claude Code."

printf '%s\n' "$_msg" >&2
jq -n --arg ctx "$_msg" \
	'{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'

exit 0
