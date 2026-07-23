#!/usr/bin/env bash
# claude/hooks/session-start-statusline-project-override.sh
#
# Claude Code SessionStart hook: re-seed the dotfiles global statusLine into a
# project that ships its own git-tracked .statusLine.
#
# Why (#1236): Claude Code merges settings with precedence
#   <project>/.claude/settings.local.json > <project>/.claude/settings.json
#   > global ~/.claude/settings.json.
# So a project whose git-tracked .claude/settings.json defines .statusLine
# overrides the dotfiles global statusline. The only personal-override slot
# that could win it back — <project>/.claude/settings.local.json — is
# gitignored, so it never survives a fresh clone / new worktree, and the
# global statusline keeps disappearing on every fresh checkout. This hook
# seeds settings.local.json (the gitignored, personal slot) with the dotfiles
# SSOT .statusLine so the global statusline persists across fresh checkouts.
#
# Idempotent + safe: never overwrites an existing local .statusLine, and only
# writes when settings.local.json is actually gitignored in that project (so
# it never dirties a working tree git would track). Missing/malformed input at
# any gate → silent no-op.
#
# Best-effort: always exits 0, never blocks the session. jq missing, no .cwd,
# no project statusLine, or already-overridden → silent no-op.
#
# Reference: issue #1236. Sibling SessionStart hooks:
# session-start-settings-drift.sh (#1086), session-start-pc-context.sh (#1052).
set -u

# A hook always receives JSON on stdin; a terminal means it was launched by
# hand — bail before `cat` blocks forever.
[ -t 0 ] && exit 0
input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null) || exit 0
[ "$event" = "SessionStart" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
[ -n "$cwd" ] || exit 0
[ -d "$cwd" ] || exit 0

# Only act if the project ships a git-tracked settings.json that itself
# defines .statusLine — otherwise there is nothing overriding the global.
PROJ_SETTINGS="$cwd/.claude/settings.json"
[ -f "$PROJ_SETTINGS" ] || exit 0
jq -e 'has("statusLine")' "$PROJ_SETTINGS" >/dev/null 2>&1 || exit 0

# Don't clobber an existing personal override.
PROJ_LOCAL="$cwd/.claude/settings.local.json"
if [ -f "$PROJ_LOCAL" ]; then
	jq -e 'has("statusLine") | not' "$PROJ_LOCAL" >/dev/null 2>&1 || exit 0
fi

# SSOT resolves relative to this script (…/claude/hooks/x.sh → …/claude), same
# pattern as session-start-settings-drift.sh. $0 is absolute (registered with
# an absolute command path).
_hook_dir=$(dirname -- "$0")
SSOT="$_hook_dir/../settings.json"
[ -f "$SSOT" ] || exit 0

ssot_sl=$(jq -c '.statusLine // empty' "$SSOT" 2>/dev/null) || exit 0
[ -n "$ssot_sl" ] || exit 0

# Safety gate: only write if settings.local.json is actually gitignored in this
# project, so we never leave a file git would track in the working tree.
if ! git -C "$cwd" check-ignore -q .claude/settings.local.json 2>/dev/null; then
	_hint="[dotfiles #1236] ${PROJ_LOCAL} is NOT gitignored in this project, so the dotfiles global statusLine was NOT seeded (writing it would dirty a git-tracked file). Add '.claude/settings.local.json' to the project's .gitignore, then restart Claude Code."
	printf '%s\n' "$_hint" >&2
	jq -n --arg ctx "$_hint" \
		'{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
	exit 0
fi

# Seed/merge .statusLine, preserving every other existing key untouched.
mkdir -p "$cwd/.claude" 2>/dev/null || exit 0
if [ -f "$PROJ_LOCAL" ]; then
	merged=$(jq --argjson sl "$ssot_sl" '.statusLine = $sl' "$PROJ_LOCAL" 2>/dev/null) || exit 0
else
	merged=$(jq -n --argjson sl "$ssot_sl" '{"statusLine": $sl}' 2>/dev/null) || exit 0
fi
[ -n "$merged" ] || exit 0
printf '%s\n' "$merged" >"$PROJ_LOCAL" 2>/dev/null || exit 0

_msg="[dotfiles #1236] Seeded the dotfiles global statusLine into ${PROJ_LOCAL} (this project's git-tracked .claude/settings.json defines its own .statusLine, which would otherwise override the global). Restart Claude Code for it to take effect."
printf '%s\n' "$_msg" >&2
jq -n --arg ctx "$_msg" \
	'{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'

exit 0
