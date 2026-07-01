#!/usr/bin/env bash
# claude/hooks/plugin-sync.sh
#
# Claude Code PostToolUse hook for `claude plugin ...` commands. Keeps
# claude/plugin/{marketplaces,plugins}.json (public, github-sourced,
# scope:user) and claude/plugin/company/{marketplaces,plugins}.json
# (private nested repo, non-github sourced) merged with the ground truth
# in ~/.claude-shared/plugins/ so claude/plugin/restore.sh can rebuild a
# fresh PC's plugin set.
#
# See docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md
#
# Always exits 0 — best-effort, never blocks the session.
set -u

# A PostToolUse hook always receives JSON on stdin. If stdin is a terminal
# the script was launched by hand — bail before `cat` blocks forever.
[ -t 0 ] && exit 0
input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""') || exit 0
[ "$tool_name" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""') || exit 0

# All manifest commits share one subject — kept in a single variable so the
# message style has exactly one edit site.
SYNC_MSG="chore(claude-plugin): sync manifest"

# Print the first non-flag argument in $1 that follows a token matching the
# `$2` keyword alternation, so flags placed between the subcommand and the
# target (e.g. `claude plugin uninstall --yes ralph-loop`) aren't mistaken
# for the target.
_extract_target() {
	printf '%s' "$1" | awk -v kw="$2" '{
        found = 0
        for (i = 1; i <= NF; i++) {
            if (found && $i !~ /^-/) {
                print $i
                exit
            }
            if ($i ~ "^(" kw ")$") {
                found = 1
            }
        }
    }'
}

action=""
target=""
if printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+marketplace[[:space:]]+add'; then
	action="add"
elif printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+marketplace[[:space:]]+(remove|rm)'; then
	action="marketplace_remove"
	target=$(_extract_target "$cmd" "remove|rm")
elif printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+install'; then
	action="add"
elif printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+(uninstall|remove)'; then
	action="uninstall"
	target=$(_extract_target "$cmd" "uninstall|remove")
else
	exit 0
fi

MAIN_ROOT="$HOME/dotfiles"
[ -d "$MAIN_ROOT/.git" ] || exit 0

SRC="$HOME/.claude-shared/plugins"
MP_SRC="$SRC/known_marketplaces.json"
PL_SRC="$SRC/installed_plugins.json"

PUB_DIR="$MAIN_ROOT/claude/plugin"
PRIV_DIR="$PUB_DIR/company"

# Stage + commit only if there is an actual diff (works for brand-new
# untracked files too, since `git diff --cached` compares the *staged*
# tree against HEAD — plain `git diff` would miss never-added files).
_commit_if_changed() {
	local repo_dir="$1" msg="$2" f
	shift 2
	# Keep only paths that exist so one missing file can't abort `git add`
	# (exit 128) and strand the others uncommitted. Rebuild the positional
	# params the POSIX-safe way (survives paths with spaces).
	for f in "$@"; do
		[ -f "$repo_dir/$f" ] && set -- "$@" "$f"
		shift
	done
	[ "$#" -gt 0 ] || return 0
	git -C "$repo_dir" add -- "$@" 2>/dev/null || return 0
	git -C "$repo_dir" diff --cached --quiet -- "$@" 2>/dev/null && return 0
	# ALLOW_MAIN_COMMIT=1: an automated manifest sync is exactly the escape
	# hatch the protected-branch guard exists for (git/hooks/checks/
	# main_branch_guard.sh). Without it, users who stay on `main` in dotfiles
	# get the commit silently blocked and reset — the manifest updates then
	# pile up unstaged and never land (#1072).
	if ! ALLOW_MAIN_COMMIT=1 git -C "$repo_dir" commit -m "$msg" --quiet 2>/dev/null; then
		# Unstage on commit failure so a failed auto-commit never leaks staged
		# changes into the user's next manual commit. Run reset first, then warn
		# to stderr with the *actual* outcome — a preemptive "left unstaged"
		# message would be wrong if the reset itself failed.
		if git -C "$repo_dir" reset -q -- "$@" 2>/dev/null; then
			printf 'plugin-sync: manifest commit failed in %s; changes left unstaged\n' \
				"$repo_dir" >&2
		else
			printf 'plugin-sync: manifest commit failed in %s; failed to unstage changes\n' \
				"$repo_dir" >&2
		fi
	fi
}

# Emit the compact JSON in file $1, or the default $2 when the file is
# missing, empty (0-byte — `jq .` exits 0 with no output there, so a plain
# `jq . || echo` fallback would not fire), or invalid JSON.
_read_json_or() {
	local out
	out=$(jq -c '.' "$1" 2>/dev/null)
	[ -n "$out" ] && printf '%s' "$out" || printf '%s' "$2"
}

# scope:user plugins from $PL_SRC whose marketplace (the part after `@`) is a
# key of the marketplace map passed as $1 (mp_common → public, mp_internal →
# private). Same filter for both sides; only the map differs.
_extract_plugins_for_mp() {
	jq -c --argjson mp "$1" '
        [(.plugins // {}) | to_entries[]
            | select(any(.value[]?; .scope == "user"))
            | .key
            | select($mp[(. | split("@") | last)] != null)
        ] | unique
    ' "$PL_SRC"
}

if [ "$action" = "add" ]; then
	[ -f "$MP_SRC" ] && [ -f "$PL_SRC" ] || exit 0

	mp_common=$(jq -c '
        [to_entries[] | select(.value.source.source == "github")]
        | map({(.key): .value.source.repo}) | add // {}
    ' "$MP_SRC") || exit 0
	mp_internal=$(jq -c '
        [to_entries[] | select(.value.source.source != "github" and .value.source.source != "directory")]
        | map({(.key): (.value.source.repo // .value.source.url // .value.source.path)}) | add // {}
    ' "$MP_SRC") || exit 0

	plugins_common=$(_extract_plugins_for_mp "$mp_common") || exit 0
	plugins_internal=$(_extract_plugins_for_mp "$mp_internal") || exit 0

	mkdir -p "$PUB_DIR"
	jq -n --argjson old "$(_read_json_or "$PUB_DIR/marketplaces.json" '{}')" \
		--argjson new "$mp_common" '$old * $new' \
		>"$PUB_DIR/marketplaces.json.tmp" &&
		mv "$PUB_DIR/marketplaces.json.tmp" "$PUB_DIR/marketplaces.json"
	jq -n --argjson old "$(_read_json_or "$PUB_DIR/plugins.json" '{"plugins":[]}')" \
		--argjson new "$plugins_common" \
		'{plugins: (($old.plugins? // []) + $new | unique | sort)}' \
		>"$PUB_DIR/plugins.json.tmp" &&
		mv "$PUB_DIR/plugins.json.tmp" "$PUB_DIR/plugins.json"
	_commit_if_changed "$MAIN_ROOT" "$SYNC_MSG" \
		claude/plugin/marketplaces.json claude/plugin/plugins.json

	if [ -d "$PRIV_DIR/.git" ] && [ "$mp_internal" != "{}" ]; then
		jq -n --argjson old "$(_read_json_or "$PRIV_DIR/marketplaces.json" '{}')" \
			--argjson new "$mp_internal" '$old * $new' \
			>"$PRIV_DIR/marketplaces.json.tmp" &&
			mv "$PRIV_DIR/marketplaces.json.tmp" "$PRIV_DIR/marketplaces.json"
		jq -n --argjson old "$(_read_json_or "$PRIV_DIR/plugins.json" '{"plugins":[]}')" \
			--argjson new "$plugins_internal" \
			'{plugins: (($old.plugins? // []) + $new | unique | sort)}' \
			>"$PRIV_DIR/plugins.json.tmp" &&
			mv "$PRIV_DIR/plugins.json.tmp" "$PRIV_DIR/plugins.json"
		_commit_if_changed "$PRIV_DIR" "$SYNC_MSG" \
			marketplaces.json plugins.json
	fi
fi

if [ "$action" = "uninstall" ] || [ "$action" = "marketplace_remove" ]; then
	[ -n "$target" ] || exit 0
	for dir in "$PUB_DIR" "$PRIV_DIR"; do
		[ -f "$dir/marketplaces.json" ] || [ -f "$dir/plugins.json" ] || continue

		if [ "$action" = "marketplace_remove" ]; then
			if [ -f "$dir/marketplaces.json" ]; then
				jq --arg t "$target" 'del(.[$t])' "$dir/marketplaces.json" \
					>"$dir/marketplaces.json.tmp" 2>/dev/null &&
					mv "$dir/marketplaces.json.tmp" "$dir/marketplaces.json"
			fi
			if [ -f "$dir/plugins.json" ]; then
				jq --arg t "$target" \
					'{plugins: [.plugins[] | select((. | split("@") | last) != $t)]}' \
					"$dir/plugins.json" >"$dir/plugins.json.tmp" 2>/dev/null &&
					mv "$dir/plugins.json.tmp" "$dir/plugins.json"
			fi
		else
			if [ -f "$dir/plugins.json" ]; then
				jq --arg t "$target" \
					'{plugins: [.plugins[] | select(. != $t and (startswith($t + "@") | not))]}' \
					"$dir/plugins.json" >"$dir/plugins.json.tmp" 2>/dev/null &&
					mv "$dir/plugins.json.tmp" "$dir/plugins.json"
			fi
		fi
	done

	_commit_if_changed "$MAIN_ROOT" "$SYNC_MSG" \
		claude/plugin/marketplaces.json claude/plugin/plugins.json
	if [ -d "$PRIV_DIR/.git" ]; then
		_commit_if_changed "$PRIV_DIR" "$SYNC_MSG" \
			marketplaces.json plugins.json
	fi
fi

exit 0
