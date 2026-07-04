#!/usr/bin/env bash
# claude/hooks/session-start-plugin-path-normalize.sh
#
# Claude Code SessionStart hook: rewrite the plugin path fields in the shared
# plugin SSOT to the ACTIVE $CLAUDE_CONFIG_DIR spelling (#1098).
#
# Why: the multi-account layout symlinks every account's plugins dir at one
# physical store —
#     ~/.claude/plugins, ~/.claude-work/plugins, ~/.claude-personal/plugins
#         → ~/.claude-shared/plugins
# so a single known_marketplaces.json / installed_plugins.json is shared across
# accounts. Claude Code 2.1.199+ validates each marketplace `installLocation`
# by a LITERAL string-prefix check against $CLAUDE_CONFIG_DIR/plugins/marketplaces
# (no symlink resolution). Whatever single spelling the shared file records, it
# is wrong for every OTHER account, so marketplace refresh fails there with
# "corrupted installLocation". This hook re-stamps the paths to the account
# that is starting up, making them physically identical but textually valid.
#
# Scope: only prefixes under ~/.claude*/plugins/ are rewritten (any sibling
# account spelling or the .claude-shared realpath). Custom/out-of-tree install
# paths are left untouched. Also normalizes installed_plugins.json installPath
# preventively — today `claude plugin list` does not validate it, but the
# install/update flows may adopt the same check.
#
# Ordering: registered BEFORE plugin-sync-session.sh in the SessionStart array
# so that hook's baseline snapshot captures the already-normalized bytes. Even
# out of order it is harmless: this hook only rewrites path VALUES, never the
# marketplace/plugin KEY SETS that plugin-sync.sh's union-merge and removal
# detection operate on, so it can never fabricate or drop a manifest entry.
#
# Best-effort: always exits 0, never blocks the session. jq missing, files
# absent, malformed JSON, or an unwritable store → silent no-op. Idempotent:
# a file is rewritten (and backed up once) ONLY when its content changes, so a
# steady state leaves mtimes untouched and produces no backup churn.
#
# Reference: issue #1098. Sibling SessionStart hooks:
# session-start-pc-context.sh (#1052), plugin-sync-session.sh (#1082),
# session-start-settings-drift.sh (#1086).
set -u

# A hook always receives JSON on stdin; a terminal means it was launched by
# hand — bail before `cat` blocks forever.
[ -t 0 ] && exit 0
input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null) || exit 0
[ "$event" = "SessionStart" ] || exit 0

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PLUGINS_DIR="$CONFIG_DIR/plugins"
[ -d "$PLUGINS_DIR" ] || exit 0

# Regex-escape $HOME so its dots/metachars are literal, then match any
# ~/.claude<suffix>/plugins/ prefix and re-point it at the active config dir.
# shellcheck disable=SC2016 # single quotes intentional — $ and & are sed syntax
HOME_RE=$(printf '%s' "$HOME" | sed 's/[.[\*^$(){}+?|/]/\\&/g')
PATTERN="^${HOME_RE}/\\.claude[^/]*/plugins/"
REPL="$PLUGINS_DIR/"

# Rewrite one JSON file in place with the given jq program, touching it (with a
# single timestamped backup) ONLY when the normalization changes semantic
# content. Change detection compares the normalized output against the ORIGINAL
# reserialized through jq too, so jq's own reformatting is neutralized on both
# sides — an already-correct file (whatever its byte formatting) is left as-is.
# That idempotence keeps mtimes stable and avoids churning plugin-sync-session's
# baseline hash on every startup.
_normalize_file() {
	file="$1"
	prog="$2"
	[ -f "$file" ] || return 0
	base=$(jq '.' "$file" 2>/dev/null) || return 0
	[ -n "$base" ] || return 0
	new=$(jq --arg pat "$PATTERN" --arg repl "$REPL" "$prog" "$file" 2>/dev/null) || return 0
	[ -n "$new" ] || return 0
	[ "$new" = "$base" ] && return 0
	cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || return 0
	tmp="$file.tmp.$$"
	printf '%s\n' "$new" >"$tmp" 2>/dev/null || return 0
	mv "$tmp" "$file" 2>/dev/null || rm -f "$tmp"
}

# shellcheck disable=SC2016 # single quotes intentional — $pat/$repl are jq vars
_normalize_file "$PLUGINS_DIR/known_marketplaces.json" '
	with_entries(
		if (.value.installLocation | type) == "string"
		then .value.installLocation |= sub($pat; $repl)
		else . end
	)
'

# shellcheck disable=SC2016 # single quotes intentional — $pat/$repl are jq vars
_normalize_file "$PLUGINS_DIR/installed_plugins.json" '
	if (.plugins | type) == "object" then
		.plugins |= with_entries(
			.value |= (
				if type == "array" then
					map(
						if (.installPath | type) == "string"
						then .installPath |= sub($pat; $repl)
						else . end
					)
				else . end
			)
		)
	else . end
'

exit 0
