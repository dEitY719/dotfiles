#!/usr/bin/env bash
# claude/hooks/plugin-sync-session.sh
#
# Companion to claude/hooks/plugin-sync.sh. The PostToolUse+Bash hook only
# fires for the shell CLI path (`$ claude plugin install ...`); the built-in
# slash commands `/plugin marketplace add|remove` and `/plugin install|uninstall`
# run inside Claude Code's UI pipeline and emit NO Bash tool call, so that hook
# never runs and the dotfiles manifest silently drifts out of sync (#1082).
#
# This hook closes the gap by watching the ground-truth SSOT files themselves,
# so it is entry-path agnostic — CLI, slash command, or any future UI path that
# mutates them is covered:
#
#   SessionStart → stash a baseline snapshot (hashes + key sets) of
#                  ~/.claude-shared/plugins/{known_marketplaces,installed_plugins}.json
#   Stop         → re-snapshot; if the hash changed vs the baseline, re-run the
#                  idempotent add/sync branch of plugin-sync.sh to pick up
#                  additions, then diff the key sets to detect removals and
#                  drive plugin-sync.sh's uninstall / marketplace-remove branch
#                  for each vanished entry (symmetric add + remove, #1082 B-1).
#
# Slash-command hook event investigation (AC): Claude Code 2.1.x exposes only
# PreToolUse / PostToolUse / UserPromptSubmit / Notification / Stop /
# SubagentStop / PreCompact / SessionStart / SessionEnd — there is NO dedicated
# hook event for built-in slash commands like `/plugin`, so Option A (a
# SlashCommand matcher) is not available. This SSOT-diff approach (Option B) is
# the entry-path-agnostic replacement and also covers the CLI path redundantly.
#
# Registered for BOTH SessionStart and Stop in claude/settings.json; branches
# on hook_event_name. Always exits 0 — best-effort, never blocks the session.
set -u

# A hook always receives JSON on stdin. If stdin is a terminal the script was
# launched by hand — bail before `cat` blocks forever.
[ -t 0 ] && exit 0
input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""') || exit 0
session_id=$(printf '%s' "$input" | jq -r '.session_id // ""') || exit 0
# Without a session id there is nowhere stable to keep the per-session baseline.
[ -n "$session_id" ] || exit 0

SRC="$HOME/.claude-shared/plugins"
MP_SRC="$SRC/known_marketplaces.json"
PL_SRC="$SRC/installed_plugins.json"

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude"
baseline="$state_dir/plugin-sync-baseline.$session_id.json"

# Snapshot the SSOT as {mp_hash, pl_hash, mp_keys, pl_keys}. A missing file
# yields an empty hash and an empty key list, so a later add/remove of that
# file is still detected as a change.
_snapshot() {
	mp_hash=$(sha256sum "$MP_SRC" 2>/dev/null | awk '{print $1}')
	pl_hash=$(sha256sum "$PL_SRC" 2>/dev/null | awk '{print $1}')
	mp_keys=$(jq -c 'keys' "$MP_SRC" 2>/dev/null) || mp_keys="[]"
	pl_keys=$(jq -c '(.plugins // {}) | keys' "$PL_SRC" 2>/dev/null) || pl_keys="[]"
	jq -n --arg mp "$mp_hash" --arg pl "$pl_hash" \
		--argjson mpk "${mp_keys:-[]}" --argjson plk "${pl_keys:-[]}" \
		'{mp_hash: $mp, pl_hash: $pl, mp_keys: $mpk, pl_keys: $plk}'
}

# Feed a synthetic `claude plugin ...` payload to the CLI-path hook so its
# add / uninstall / marketplace-remove branches do the actual manifest work —
# one implementation, reused from both entry paths.
_drive_sync() {
	printf '{"tool_name":"Bash","tool_input":{"command":"claude plugin %s"}}' "$1" |
		"$SYNC_HOOK" >&2 || true
}

if [ "$event" = "SessionStart" ]; then
	mkdir -p "$state_dir" 2>/dev/null || exit 0
	_snapshot >"$baseline" 2>/dev/null || true
	# Prune stale per-session baselines (crash-left or long-abandoned) so the
	# state dir doesn't grow without bound.
	find "$state_dir" -maxdepth 1 -name 'plugin-sync-baseline.*.json' \
		-mtime +7 -delete 2>/dev/null || true
	exit 0
fi

# --- Stop (or any non-SessionStart event registered here) ---

[ -f "$MP_SRC" ] || exit 0
SYNC_HOOK="$HOME/dotfiles/claude/hooks/plugin-sync.sh"
[ -x "$SYNC_HOOK" ] || exit 0

now=$(_snapshot) || exit 0
now_mp=$(printf '%s' "$now" | jq -r '.mp_hash')
now_pl=$(printf '%s' "$now" | jq -r '.pl_hash')

changed=1
prev_mp_keys="[]"
prev_pl_keys="[]"
if [ -f "$baseline" ]; then
	prev_mp=$(jq -r '.mp_hash // ""' "$baseline" 2>/dev/null)
	prev_pl=$(jq -r '.pl_hash // ""' "$baseline" 2>/dev/null)
	prev_mp_keys=$(jq -c '.mp_keys // []' "$baseline" 2>/dev/null) || prev_mp_keys="[]"
	prev_pl_keys=$(jq -c '.pl_keys // []' "$baseline" 2>/dev/null) || prev_pl_keys="[]"
	[ "$prev_mp" = "$now_mp" ] && [ "$prev_pl" = "$now_pl" ] && changed=0
fi

[ "$changed" -eq 1 ] || exit 0

# 1) Additions / re-sync. plugin-sync.sh's add branch ignores the target and
# rebuilds the manifest from the SSOT via idempotent union merge, so a dummy
# target is fine and a no-op run creates no commit.
_drive_sync "install __slash_command_sync__"

# 2) Removals. Marketplaces / plugins present at the baseline but gone now must
# be dropped from the manifest — the union merge above never removes anything.
now_mp_keys=$(printf '%s' "$now" | jq -c '.mp_keys')
now_pl_keys=$(printf '%s' "$now" | jq -c '.pl_keys')

removed_mp=$(jq -n -r --argjson a "$prev_mp_keys" --argjson b "$now_mp_keys" '($a - $b)[]' 2>/dev/null)
while IFS= read -r mp; do
	[ -n "$mp" ] || continue
	_drive_sync "marketplace remove $mp"
done <<EOF
$removed_mp
EOF

removed_pl=$(jq -n -r --argjson a "$prev_pl_keys" --argjson b "$now_pl_keys" '($a - $b)[]' 2>/dev/null)
while IFS= read -r pl; do
	[ -n "$pl" ] || continue
	_drive_sync "uninstall $pl"
done <<EOF
$removed_pl
EOF

# 3) Refresh the baseline to the current SSOT (our sync mutates only the
# dotfiles manifest, never the SSOT, so `now` is still accurate).
mkdir -p "$state_dir" 2>/dev/null || exit 0
printf '%s' "$now" >"$baseline" 2>/dev/null || true

exit 0
