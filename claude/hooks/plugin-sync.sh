#!/usr/bin/env bash
# claude/hooks/plugin-sync.sh
#
# Claude Code PostToolUse hook for `claude plugin ...` commands. Keeps
# claude/plugin/{marketplaces,plugins}.local.json (public, github-sourced,
# scope:user) and claude/plugin/company/{marketplaces,plugins}.json
# (private nested repo, non-github sourced) merged with the ground truth
# in ~/.claude-shared/plugins/ so claude/plugin/restore.sh can rebuild a
# fresh PC's plugin set.
#
# #1685 — the public pair this hook writes is the gitignored `.local.json`
# OVERLAY, never the tracked claude/plugin/{marketplaces,plugins}.json. Those
# tracked files are the upstream-owned REGISTRATION CONTRACT (changed by PRs,
# pinned by claude_plugin_{restore,scaffold}.bats); this hook only reads them,
# to subtract their entries from the overlay. Before the split, both writers
# appended to the same tracked array, so every fork/mirror conflicted with
# every upstream registration commit — and the public
# "chore(claude-plugin): sync manifest" auto-commit this hook used to make is
# gone with it (an untracked overlay has nothing to commit). company/ is a
# separate private repo with no fork to diverge from, so it still commits.
#
# See docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md
#
# Always exits 0 — best-effort, never blocks the session.
#
# Set DOTFILES_PLUGIN_SYNC_DISABLED=1 (e.g. in settings.local.json's "env")
# to turn manifest auto-sync/auto-commit off. plugin-sync-session.sh
# (SessionStart/Stop) drives its add/remove work through this script too, so
# gating here covers both the CLI path and the /plugin slash-command path.
set -u

[ -z "${DOTFILES_PLUGIN_SYNC_DISABLED-}" ] || exit 0

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
	target=$(_extract_target "$cmd" "add")
elif printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+marketplace[[:space:]]+(remove|rm)'; then
	action="marketplace_remove"
	target=$(_extract_target "$cmd" "remove|rm")
elif printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+install'; then
	action="add"
	target=$(_extract_target "$cmd" "install")
elif printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+(uninstall|remove)'; then
	action="uninstall"
	target=$(_extract_target "$cmd" "uninstall|remove")
else
	exit 0
fi

# claude/hooks/plugin-sync-session.sh drives this same "add" branch with a
# reserved dummy target (__slash_command_sync__) to trigger a full SSOT
# re-sync that can add several plugins/marketplaces at once — not a single
# real install. Naming that placeholder in the commit title would mislead
# more than the plain title does, so it never reaches the title (#1430).
# The bulk path instead names the keys it actually changed, computed just
# before the write (#1558) — the bare subject it used to get made an
# eleven-plugin re-sync indistinguishable from a no-op one in `git log`.
BULK_RESYNC=0
if [ "$target" = "__slash_command_sync__" ]; then
	BULK_RESYNC=1
	target=""
fi

# Commit title: name the single install/uninstall target when known, so
# `git log --oneline` distinguishes syncs instead of showing the same
# subject for every plugin change (#1430). Falls back to the bare SYNC_MSG
# when no target was parsed (unrecognized command shape, or the sentinel
# above — see _resolve_sync_title for what the sentinel path uses instead).
SYNC_TITLE="$SYNC_MSG"
[ -n "$target" ] && SYNC_TITLE="$SYNC_MSG ($target)"

MAIN_ROOT="$HOME/dotfiles"
[ -d "$MAIN_ROOT/.git" ] || exit 0

# Title helper shared with claude/plugin/reconcile.sh --apply so both writers
# of this commit emit one format (#1558). Sourced below the repo check above
# because a PC with no dotfiles checkout exits before the title can matter.
# Best-effort like the rest of the hook: a missing helper (stale install) just
# leaves _resolve_sync_title falling back to $SYNC_TITLE.
# shellcheck disable=SC1091
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/plugin_sync_title.sh" 2>/dev/null || true
# The manifest reader (_claude_plugin_read_json_or) is the same helper
# reconcile.sh and restore.sh need, so it has a single home in shell-common
# (#1696).
# shellcheck disable=SC1091
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/claude_plugin_manifest.sh" 2>/dev/null || true

# Bootstrap fallback, NOT a second implementation to maintain in parallel.
# The title helper may go missing and the hook simply commits under the bare
# subject, but the reader feeds `jq --argjson` for the merge itself: without it
# the merged value comes out empty, _write_manifest refuses to write, and the
# manifest update is lost silently. A stale install must still sync (pinned by
# tests/bats/skills/plugin_sync_hook.bats "falls back to the bare subject when
# the title helper is unavailable", which asserts the commit still lands).
# Behavior changes belong in shell-common/functions/claude_plugin_manifest.sh;
# this copy follows it.
if ! command -v _claude_plugin_read_json_or >/dev/null 2>&1; then
	_claude_plugin_read_json_or() {
		local out=""
		if [ -f "$1" ]; then
			out=$(jq -c '.' "$1" 2>/dev/null)
		fi
		if [ -n "$out" ]; then
			printf '%s' "$out"
		else
			printf '%s' "$2"
		fi
	}
fi

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
		return 0
	fi
	# The commit succeeded — push it if it landed on a protected branch (#1125).
	_push_if_protected "$repo_dir"
}

# Push the just-committed branch when it is a protected branch (main/master).
# ALLOW_MAIN_COMMIT lets the manifest commit land directly on main (#1072), but
# an unpushed commit on main diverges the moment origin/main advances via a
# merged PR — which then makes `gwt teardown`'s ff-only main-sync refuse (#1125).
# Pushing right away keeps local main == origin/main so no local-only commit
# lingers. Best-effort: no upstream / offline / branch-protection rejection just
# leaves today's local-only commit plus a stderr hint — the hook still exits 0.
_push_if_protected() {
	local repo_dir="$1" branch upstream
	branch=$(git -C "$repo_dir" symbolic-ref --short HEAD 2>/dev/null) || return 0
	case "$branch" in
	main | master) ;;
	*) return 0 ;;
	esac
	# Never guess a remote — only push when the branch has a configured upstream.
	upstream=$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || return 0
	[ -n "$upstream" ] || return 0
	if ! git -C "$repo_dir" push --quiet 2>/dev/null; then
		printf 'plugin-sync: manifest committed on protected %s in %s but push to %s failed; commit is local-only (rebase/push before it diverges from origin)\n' \
			"$branch" "$repo_dir" "$upstream" >&2
	fi
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

# Replace manifest $1 with content $2 atomically. An empty $2 means the jq
# that produced it failed — leave the file alone rather than truncating it
# (the older `jq ... >tmp && mv` form got that for free).
_write_manifest() {
	[ -n "$2" ] || return 0
	# Don't CREATE a file whose content is empty (#1695 agy FOLLOW-UP): a
	# contract-only machine — every installed entry already registered
	# upstream — subtracts down to `{}` / `{"plugins":[]}`, and writing that
	# leaves two puzzling empty overlays behind. An existing file is still
	# rewritten, so a real emptying (last local extra uninstalled) lands.
	if [ ! -f "$1" ]; then
		case "$2" in
		'{}' | '{"plugins":[]}' | '{ "plugins": [] }') return 0 ;;
		esac
		# `jq -n '{plugins: $p}'` pretty-prints, so compare structurally too.
		if [ "$(printf '%s' "$2" | jq -c '. as $x | ($x == {}) or ($x == {plugins:[]})' 2>/dev/null)" = "true" ]; then
			return 0
		fi
	fi
	printf '%s\n' "$2" >"$1.tmp" && mv "$1.tmp" "$1"
}

# --- 계약 항목 묘비 (#1695 agy BLOCKER) -------------------------------------
# 이 훅은 tracked 등록 계약을 쓰지 않는다. 그래서 계약에 있는 플러그인을
# uninstall 하면 오버레이에서만 빠지고, restore.sh 는 계약을 보고 그대로 다시
# 설치한다 — #1685 이전에는 훅이 계약 파일에서 지웠으므로 동작 퇴행이다.
# 묘비 파일이 그 "이 PC 에서는 지웠다" 는 사실을 머신 로컬로 기록하고,
# restore.sh 의 union 이 이것을 뺀다. 계약은 여전히 손대지 않는다.
TOMBSTONE="$PUB_DIR/removed.local.json"

# 묘비에 $2 를 추가한다. $1 은 "marketplaces" 또는 "plugins".
_tombstone_add() {
	local kind="$1" name="$2" out
	out=$(jq -n --argjson old "$(_claude_plugin_read_json_or "$TOMBSTONE" '{}')" \
		--arg k "$kind" --arg n "$name" \
		'$old | .[$k] = (((.[$k] // []) + [$n]) | unique)' 2>/dev/null) || return 0
	[ -n "$out" ] || return 0
	mkdir -p "$PUB_DIR"
	printf '%s\n' "$out" >"$TOMBSTONE.tmp" && mv "$TOMBSTONE.tmp" "$TOMBSTONE"
}

# 다시 설치된 항목의 묘비를 지운다 — 지우지 않으면 재설치가 restore.sh 에서
# 되돌려진다. add 분기에서 SSOT 에 실제로 존재하는 것들을 통째로 뺀다.
# $1 = 현재 설치된 plugin id 배열(JSON), $2 = 현재 마켓플레이스 이름 배열(JSON).
_tombstone_clear_installed() {
	[ -f "$TOMBSTONE" ] || return 0
	local out
	out=$(jq -n --argjson old "$(_claude_plugin_read_json_or "$TOMBSTONE" '{}')" \
		--argjson pl "$1" --argjson mp "$2" \
		'{marketplaces: ((($old.marketplaces // []) - $mp)),
		  plugins:      ((($old.plugins // []) - $pl))}' 2>/dev/null) || return 0
	[ -n "$out" ] || return 0
	printf '%s\n' "$out" >"$TOMBSTONE.tmp" && mv "$TOMBSTONE.tmp" "$TOMBSTONE"
}

# Commit title for one manifest pair. A single install/uninstall keeps the
# "(<target>)" title #1430 gave it; the SessionStart bulk re-sync has no
# single target, so it names the keys this run actually changes (#1558),
# in reconcile.sh --apply's format.
#
# $1/$3 are the manifest files as they still are on disk (call before the
# write); $2/$4 are the MERGED values about to be written. Diffing against
# the merged value rather than the raw SSOT target is what keeps the title
# honest — this path unions and never deletes, so an entry the merge
# preserves must never be reported as "-entry".
#
# Any failure (helper not sourced, jq error, malformed manifest) degrades to
# the bare subject: this hook always exits 0.
_resolve_sync_title() {
	if [ "$BULK_RESYNC" != "1" ] || ! command -v _plugin_sync_title >/dev/null 2>&1; then
		printf '%s' "$SYNC_TITLE"
		return 0
	fi
	_plugin_sync_title "$SYNC_MSG" "$1" "$2" "$3" "$4"
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
	# Public scope writes the gitignored overlay only (#1685). The tracked
	# contract is read to SUBTRACT its entries from the overlay target: an
	# entry upstream already registers must not be duplicated here, or a later
	# contract change would be silently re-added by this machine's overlay.
	# Nothing tracked changes, so there is no commit and no fork conflict.
	mp_tracked=$(_claude_plugin_read_json_or "$PUB_DIR/marketplaces.json" '{}')
	pl_tracked=$(_claude_plugin_read_json_or "$PUB_DIR/plugins.json" '{"plugins":[]}')
	mp_pub=$(jq -n --argjson old "$(_claude_plugin_read_json_or "$PUB_DIR/marketplaces.local.json" '{}')" \
		--argjson new "$mp_common" --argjson tracked "$mp_tracked" \
		'($old * $new) | with_entries(select($tracked[.key] == null))')
	pl_pub=$(jq -n --argjson old "$(_claude_plugin_read_json_or "$PUB_DIR/plugins.local.json" '{"plugins":[]}')" \
		--argjson new "$plugins_common" --argjson tracked "$pl_tracked" \
		'((($old.plugins? // []) + $new) - ($tracked.plugins? // []) | unique | sort)')
	_write_manifest "$PUB_DIR/marketplaces.local.json" "$mp_pub"
	_write_manifest "$PUB_DIR/plugins.local.json" "$(jq -n --argjson p "$pl_pub" '{plugins: $p}')"
	# 재설치는 묘비를 취소한다 (#1695). SSOT 에 실제로 있는 것만 지우므로,
	# 손대지 않은 다른 묘비는 그대로 남는다.
	_tombstone_clear_installed "$plugins_common" \
		"$(jq -n --argjson m "$mp_common" '$m | keys')"

	if [ -d "$PRIV_DIR/.git" ] && [ "$mp_internal" != "{}" ]; then
		# Its own commit over its own files, so its own title — reusing the
		# public one would name public keys in a private-repo commit.
		mp_priv=$(jq -n --argjson old "$(_claude_plugin_read_json_or "$PRIV_DIR/marketplaces.json" '{}')" \
			--argjson new "$mp_internal" '$old * $new')
		pl_priv=$(jq -n --argjson old "$(_claude_plugin_read_json_or "$PRIV_DIR/plugins.json" '{"plugins":[]}')" \
			--argjson new "$plugins_internal" \
			'(($old.plugins? // []) + $new | unique | sort)')
		priv_title=$(_resolve_sync_title \
			"$PRIV_DIR/marketplaces.json" "$mp_priv" "$PRIV_DIR/plugins.json" "$pl_priv")
		_write_manifest "$PRIV_DIR/marketplaces.json" "$mp_priv"
		_write_manifest "$PRIV_DIR/plugins.json" "$(jq -n --argjson p "$pl_priv" '{plugins: $p}')"
		_commit_if_changed "$PRIV_DIR" "$priv_title" \
			marketplaces.json plugins.json
	elif [ "$mp_internal" != "{}" ] && [ ! -d "$PRIV_DIR/.git" ]; then
		# 사내(non-github) 마켓플레이스가 감지됐지만 이 PC 에는 company/ 레포가
		# clone 돼 있지 않다 — external/public PC 에서 사내 GHES 마켓플레이스가
		# 우연히 설치된 경우다. 저장하지 않는 건 사내→사외 격리 정책이자 의도된
		# 동작이지만, 예전엔 조용히 skip 해 사용자가 "왜 매니페스트에 아무 것도
		# 안 남지?" 라고 헷갈렸다 (#1080). 저장은 여전히 하지 않고, 다음 액션을
		# 알 수 있도록 stderr 힌트만 남긴다 (exit 0 원칙은 그대로).
		printf 'plugin-sync: 사내 GHES 마켓플레이스 감지 — 이 PC 에는 company/ 레포가 없습니다 (external/public PC 로 판단)\n' >&2
		printf 'plugin-sync:   → 격리 정책상 %s 에 저장하지 않습니다 (사내 URL 이 공개 레포로 유출되지 않도록)\n' "$PRIV_DIR" >&2
		printf 'plugin-sync:   → internal PC 에서 관리하세요. 이 PC 에서도 관리하려면 먼저: git clone <GHES private repo url> "%s"\n' "$PRIV_DIR" >&2
	fi
fi

# Rewrite manifest $1 through jq filter $2 (with `$t` bound to $target). A jq
# failure yields empty content, which _write_manifest refuses to write — so a
# malformed manifest is left alone rather than truncated.
_prune_one() {
	[ -f "$1" ] || return 0
	_write_manifest "$1" "$(jq --arg t "$target" "$2" "$1" 2>/dev/null)"
}

# Drop $target from ONE manifest pair — $1 marketplaces file, $2 plugins file.
# Takes the pair as arguments rather than a directory because the two scopes no
# longer share a filename: public prunes the .local.json overlay, company/ its
# own tracked pair (#1685).
_prune_manifest_pair() {
	if [ "$action" = "marketplace_remove" ]; then
		_prune_one "$1" 'del(.[$t])'
		_prune_one "$2" '{plugins: [(.plugins // [])[] | select((. | split("@") | last) != $t)]}'
	else
		_prune_one "$2" '{plugins: [(.plugins // [])[] | select(. != $t and (startswith($t + "@") | not))]}'
	fi
}

# One stderr line when the uninstalled entry ALSO sits in the tracked
# registration contract (#1685). This hook deliberately never edits that file,
# so without the hint the user would see restore.sh reinstall the plugin on the
# next run with no explanation. Advisory only — never blocks, never writes.
_warn_if_contract_entry() {
	local hit file
	if [ "$action" = "marketplace_remove" ]; then
		file="marketplaces.json"
		hit=$(jq -r --arg t "$target" 'select(has($t)) | $t' \
			"$PUB_DIR/marketplaces.json" 2>/dev/null)
	else
		file="plugins.json"
		hit=$(jq -r --arg t "$target" \
			'first((.plugins // [])[] | select(. == $t or startswith($t + "@"))) // empty' \
			"$PUB_DIR/plugins.json" 2>/dev/null)
	fi
	[ -n "$hit" ] || return 0
	# 계약은 그대로 두고, "이 PC 에서는 지웠다" 를 묘비로 남긴다 (#1695).
	# 이것이 restore.sh 의 재설치 퇴행을 막는다 — 계약 편집은 여전히 PR 의 일이다.
	if [ "$action" = "marketplace_remove" ]; then
		_tombstone_add marketplaces "$hit"
	else
		_tombstone_add plugins "$hit"
	fi
	printf 'plugin-sync: %s 는 claude/plugin/%s (upstream 등록 계약) 에도 있습니다 — 계약은 그대로 두고 %s 에 묘비를 남깁니다 (#1685)\n' \
		"$hit" "$file" "$(basename "$TOMBSTONE")" >&2
	printf 'plugin-sync:   → 이 PC 에서는 restore.sh 가 더 이상 설치하지 않습니다. 모든 PC 에서 빼려면 별도 PR 로 계약 파일을 편집하세요.\n' >&2
}

if [ "$action" = "uninstall" ] || [ "$action" = "marketplace_remove" ]; then
	[ -n "$target" ] || exit 0

	# 공용: gitignored 오버레이에서만 지운다 — 커밋 없음, tracked 변경 없음.
	_prune_manifest_pair "$PUB_DIR/marketplaces.local.json" "$PUB_DIR/plugins.local.json"
	_warn_if_contract_entry

	# company/ 는 별도 private 레포라 fork 가 없다 — tracked pair + 커밋 유지.
	_prune_manifest_pair "$PRIV_DIR/marketplaces.json" "$PRIV_DIR/plugins.json"
	if [ -d "$PRIV_DIR/.git" ]; then
		_commit_if_changed "$PRIV_DIR" "$SYNC_TITLE" \
			marketplaces.json plugins.json
	fi
fi

exit 0
