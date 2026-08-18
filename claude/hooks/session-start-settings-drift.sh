#!/usr/bin/env bash
# claude/hooks/session-start-settings-drift.sh
#
# Claude Code SessionStart hook: keep the live ~/.claude*/settings.json
# `.hooks` + `.statusLine` blocks in sync with the dotfiles SSOT
# (claude/settings.json) — self-healing on internal PCs, advisory elsewhere.
#
# Why (#1086): in every mode the live settings.json is a REAL FILE, not a
# symlink — multi-account copies the SSOT (#940), internal used to
# deep-merge SSOT + Bedrock overlay via aws/setup.sh (#687). So a commit that
# adds or changes a hook in the SSOT does NOT reach the live file until a
# re-seed script is run. A user who only `git pull`s + restarts Claude Code
# starts sessions with the OLD hook set, so new hooks silently never fire —
# the concrete failure mode that hid plugin-sync-session.sh for ~1h.
#
# Why it now HEALS instead of only warning (2026-08-18): the org's LLM Gateway
# migration made `gateway-cli setup` the owner of the internal-PC live
# settings.json (apiKeyHelper / awsCredentialExport / awsAuthRefresh /
# cleanupPeriodDays / env.*), and `aws/setup.sh`'s merge — the ONLY thing that
# ever carried SSOT `.hooks`/`.statusLine` changes into an internal PC's live
# file — was deprecated to stop the two writers from ping-ponging. That left
# internal PCs with a detector whose remediation ("re-run ./aws/setup.sh") no
# longer does anything. Worse, gateway-cli's own `setup` OVERWRITES
# `.statusLine.command` with its (currently placeholder-printing) binary, so
# `.statusLine` drift is not hypothetical — it is what actually happened and
# it is invisible without this hook. Hence: internal mode patches the two
# dotfiles-owned keys back in place, every session, automatically.
#
# Scope of the write is deliberately tiny — ONLY `.hooks` and `.statusLine`
# are assigned, via jq, into the existing document. Every other key's VALUE
# is left alone: gateway-cli's (apiKeyHelper, awsCredentialExport,
# awsAuthRefresh, cleanupPeriodDays, env, model, availableModels), Claude
# Code's own (enabledPlugins, extraKnownMarketplaces), and anything a user or
# a future tool adds. dotfiles claims no other key in the live file.
# (Not literally byte-for-byte: jq re-serializes the whole document on write,
# so whitespace/key-order and — in the unlikely event a value is a very large
# integer or a high-precision float — numeric formatting can change. No
# gateway-cli/Claude-Code key currently holds such a value.)
#
# Which keys are compared, and why exactly these two: they are the only
# settings.json fields that dotfiles ships as behaviour (hook wiring + the
# statusline command path) rather than as auth/model configuration. The old
# Bedrock overlay never touched either, and gateway-cli only touches
# `.statusLine` (by accident), so SSOT-vs-live inequality on these two always
# means the live file is stale, clobbered, or hand-edited — never a legitimate
# per-PC difference.
#
# Non-internal modes keep the pre-existing advisory-only behaviour: their
# re-seed path (`./setup.sh` → claude/setup.sh's real-file copy, #940) is
# still valid, so there is nothing to work around and no reason to start
# writing to a file that setup.sh owns.
#
# Safety rails on the heal path:
#   - Backup first, to ${HOME}/.claude-backups/ (NEVER inside the dotfiles
#     tree — the live file can hold plaintext internal tokens, #554), with a
#     fixed latest-only suffix per #919/#806 and a sweep of pre-#919
#     timestamped leftovers.
#   - A key is only healed when the SSOT actually DEFINES it; a missing SSOT
#     value degrades to advisory rather than deleting the live one.
#   - A symlinked live file is never rewritten (that layout is owned by
#     whoever created the symlink) — advisory only.
#   - Any jq/cp/mv failure degrades to the advisory message. The backup is
#     kept so a partial state is always recoverable by hand.
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

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null) || exit 0
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

# `.hooks` compares with `// {}` (an absent block and an empty one are the same
# thing); `.statusLine` compares with `// null` so "SSOT does not define it"
# stays distinguishable from "SSOT defines it as {}" — the heal path needs that
# distinction to avoid deleting a live value it has no replacement for.
ssot_hooks=$(jq -S -c '.hooks // {}' "$SSOT" 2>/dev/null) || exit 0
live_hooks=$(jq -S -c '.hooks // {}' "$LIVE" 2>/dev/null) || exit 0
ssot_statusline=$(jq -S -c '.statusLine // null' "$SSOT" 2>/dev/null) || exit 0
live_statusline=$(jq -S -c '.statusLine // null' "$LIVE" 2>/dev/null) || exit 0

_drift_hooks=0
_drift_statusline=0
[ "$ssot_hooks" = "$live_hooks" ] || _drift_hooks=1
[ "$ssot_statusline" = "$live_statusline" ] || _drift_statusline=1

# Fast path: nothing dotfiles owns has drifted.
[ "$_drift_hooks" -eq 1 ] || [ "$_drift_statusline" -eq 1 ] || exit 0

_drift_keys=""
[ "$_drift_hooks" -eq 1 ] && _drift_keys=".hooks"
[ "$_drift_statusline" -eq 1 ] && _drift_keys="${_drift_keys:+${_drift_keys}, }.statusLine"

# --- Mode detection (same canonicalisation the rest of the repo uses) -------
_mode=""
if [ -f "$HOME/.dotfiles-setup-mode" ]; then
	_raw=$(tr -d ' \t\n\r' <"$HOME/.dotfiles-setup-mode" 2>/dev/null)
	case "$_raw" in
	2 | internal) _mode="internal" ;;
	esac
fi

# --- Internal mode: auto-heal the two dotfiles-owned keys in place ---------
_healed=0
_healed_statusline=0
_backup=""
if [ "$_mode" = "internal" ] && [ ! -L "$LIVE" ]; then
	# Build the jq assignment for the drifted keys only. A drifted
	# `.statusLine` that the SSOT does not define is intentionally skipped —
	# healing it would mean deleting the live value with nothing to put back.
	# `_healed_keys` tracks only what `_prog` actually assigns — kept
	# separate from `_drift_keys` (which is "what differs") so the message
	# below never claims a key was healed when it was silently skipped here.
	_prog=""
	_healed_keys=""
	# Single quotes are deliberate: `$ssot_hooks` / `$ssot_statusline` are jq
	# --argjson variable names, not shell variables.
	# shellcheck disable=SC2016
	if [ "$_drift_hooks" -eq 1 ]; then
		_prog='.hooks = $ssot_hooks'
		_healed_keys=".hooks"
	fi
	if [ "$_drift_statusline" -eq 1 ] && [ "$ssot_statusline" != "null" ]; then
		_prog="${_prog:+${_prog} | }.statusLine = \$ssot_statusline"
		_healed_keys="${_healed_keys:+${_healed_keys}, }.statusLine"
		_healed_statusline=1
	fi

	if [ -n "$_prog" ]; then
		_backup_dir="${HOME}/.claude-backups"
		# Latest-only backup (#919); the glob sweeps pre-#919 timestamped
		# leftovers. SSOT policy: shell-common/functions/dotfiles_backup.sh (#806).
		_backup="${_backup_dir}/settings.json.pre-drift-heal.backup"
		_tmp=""
		if mkdir -p "$_backup_dir" 2>/dev/null &&
			cp "$LIVE" "$_backup" 2>/dev/null &&
			chmod 0600 "$_backup" 2>/dev/null &&
			_tmp=$(mktemp "${LIVE}.XXXXXX" 2>/dev/null) &&
			jq --argjson ssot_hooks "$ssot_hooks" \
				--argjson ssot_statusline "$ssot_statusline" \
				"$_prog" "$LIVE" >"$_tmp" 2>/dev/null &&
			[ -s "$_tmp" ] &&
			chmod 0600 "$_tmp" 2>/dev/null &&
			mv -f "$_tmp" "$LIVE" 2>/dev/null; then
			rm -f "${_backup_dir}/settings.json.pre-drift-heal-"*
			_healed=1
		else
			# Degrade to advisory. Leave the backup in place — a half-written
			# temp file is the only thing worth cleaning up here.
			[ -n "$_tmp" ] && rm -f "$_tmp"
			_backup=""
		fi
	fi
fi

# --- Message ---------------------------------------------------------------
# Both branches keep the literal "hook drift" phrase so log greps / existing
# regression tests written against the advisory wording keep matching.
if [ "$_healed" -eq 1 ]; then
	# `_drift_statusline` can be 1 while `.statusLine` was skipped by the heal
	# (SSOT doesn't define it) — say so explicitly instead of letting the
	# "auto-corrected" claim silently cover a key that is still drifted.
	_leftover=""
	if [ "$_drift_statusline" -eq 1 ] && [ "$_healed_statusline" -ne 1 ]; then
		_leftover=".statusLine (SSOT 값 없음 — 자동 복구 불가, 수동 확인 필요)"
	fi
	_msg="[dotfiles #1086] Claude settings.json hook drift auto-corrected: the live config (${LIVE}) had drifted from the dotfiles SSOT (claude/settings.json) in: ${_healed_keys}. Internal-PC mode patched ONLY those keys back in place — gateway-cli-owned keys (apiKeyHelper / awsCredentialExport / awsAuthRefresh / cleanupPeriodDays / env / model) were not touched. No action needed; restart Claude Code if you want the restored hooks/statusLine active in THIS session. Backup: ${_backup}${_leftover:+ | NOT auto-corrected: ${_leftover}}"
else
	# Non-internal PCs (and the internal fallbacks: symlinked live file, SSOT
	# does not define the drifted key, or a failed patch) re-seed by hand.
	_reseed="./setup.sh"
	[ "$_mode" = "internal" ] && _reseed="gateway-cli setup   # then re-check; dotfiles no longer re-seeds settings.json"
	_msg="[dotfiles #1086] Claude settings.json hook drift: the live config (${LIVE}) differs from the dotfiles SSOT (claude/settings.json) in: ${_drift_keys}. New or changed hooks/statusLine will NOT take effect until the live file is re-seeded — run ${_reseed} in your dotfiles checkout, then restart Claude Code."
fi

printf '%s\n' "$_msg" >&2
jq -n --arg ctx "$_msg" \
	'{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'

exit 0
