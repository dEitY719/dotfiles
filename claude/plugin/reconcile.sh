#!/usr/bin/env bash
# claude/plugin/reconcile.sh
#
# Full-recompute drift detector/repair for the dotfiles plugin manifests.
#
# claude/hooks/plugin-sync.sh keeps claude/plugin/{marketplaces,plugins}.json
# (and, on internal PCs, claude/plugin/company/*) up to date INCREMENTALLY —
# it only patches the manifest when it observes a `claude plugin ...` command.
# Any event it misses (crash, sync from another PC, a manual edit) leaves a
# ghost entry the hook can never remove, because there is no local event to
# key the delete off of.
#
# reconcile.sh closes that gap: it treats ~/.claude-shared/plugins/
# {known_marketplaces,installed_plugins}.json as the SSOT and rebuilds the
# dotfiles manifest to match it EXACTLY (adds missing entries AND prunes
# ghosts). It reuses the same jq selection rules as plugin-sync.sh so the two
# never disagree on which marketplaces/plugins are in scope; the only
# difference is that reconcile recomputes the whole set instead of patching
# one entry.
#
#   --check (default)  print SSOT-vs-manifest diff; non-zero exit if drift
#   --apply            rewrite the manifest to match SSOT, commit if changed
#
# Public (github) marketplaces route to claude/plugin/*.json; private
# (non-github) ones to claude/plugin/company/*.json — identical to the hook.
# company/ is processed only on an `internal` PC with the nested repo cloned.
#
# See docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md
set -uo pipefail

MODE_ACTION="check"

_usage() {
	cat <<'EOF'
Usage: reconcile.sh [--check|--apply] [-h|--help]

  --check   (기본) SSOT(~/.claude-shared/plugins) 와 dotfiles 매니페스트의
            drift 를 표로 출력한다. drift 가 있으면 non-zero 로 종료한다.
  --apply   dotfiles 매니페스트를 SSOT 기준으로 재빌드하고 (유령 엔트리 제거
            포함), 변경이 있으면 "chore(claude-plugin): sync manifest" 커밋을
            하나 남긴다.
  -h, --help  이 도움말 출력 후 종료.

SSOT: ~/.claude-shared/plugins/{known_marketplaces,installed_plugins}.json
      (CLAUDE_SHARED_PLUGINS_DIR 로 재정의 가능)
공용(github) → claude/plugin/*.json, 사내(non-github) → claude/plugin/company/*.json
company/ 는 ~/.dotfiles-setup-mode == internal 이고 company/.git 이 있을 때만 처리.
EOF
}

for arg in "$@"; do
	case "$arg" in
	--check) MODE_ACTION="check" ;;
	--apply) MODE_ACTION="apply" ;;
	-h | --help | help)
		_usage
		exit 0
		;;
	*)
		echo "알 수 없는 인자: $arg" >&2
		_usage >&2
		exit 2
		;;
	esac
done

command -v jq >/dev/null 2>&1 || {
	echo "jq가 필요합니다." >&2
	exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUB_DIR="$SCRIPT_DIR"
PRIV_DIR="$SCRIPT_DIR/company"

# The repo that owns the public manifest — resolved from SCRIPT_DIR so this
# works from any checkout/worktree (and from a test copy). Required for
# --apply's commit; --check never needs it.
MAIN_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"

SHARED_DIR="${CLAUDE_SHARED_PLUGINS_DIR:-$HOME/.claude-shared/plugins}"
MP_SRC="$SHARED_DIR/known_marketplaces.json"
PL_SRC="$SHARED_DIR/installed_plugins.json"

SYNC_MSG="chore(claude-plugin): sync manifest"

# internal PC + cloned company/ repo → the private manifest is in scope.
# `.git` is a *file* in a worktree, so probe with `git rev-parse --git-dir`
# rather than `[ -d .git ]` (worktree-safe, matches the repo convention).
MODE=""
if [ -f "$HOME/.dotfiles-setup-mode" ]; then
	MODE=$(cat "$HOME/.dotfiles-setup-mode")
fi
COMPANY_ACTIVE=0
if [ "$MODE" = "internal" ] && git -C "$PRIV_DIR" rev-parse --git-dir >/dev/null 2>&1; then
	COMPANY_ACTIVE=1
fi

for f in "$MP_SRC" "$PL_SRC"; do
	if [ ! -f "$f" ]; then
		echo "SSOT 파일이 없습니다: $f" >&2
		echo "  → ~/.claude-shared/plugins 를 확인하거나 CLAUDE_SHARED_PLUGINS_DIR 를 설정하세요." >&2
		exit 1
	fi
done

# --- SSOT → target set (jq rules mirror plugin-sync.sh) -------------------

# github-sourced marketplaces → {name: repo}
target_common=$(jq -c '
    [to_entries[] | select(.value.source.source == "github")]
    | map({(.key): .value.source.repo}) | add // {}
' "$MP_SRC") || exit 1
# everything else except source:directory (machine-local) → {name: url|repo|path}
target_private=$(jq -c '
    [to_entries[] | select(.value.source.source != "github" and .value.source.source != "directory")]
    | map({(.key): (.value.source.repo // .value.source.url // .value.source.path)}) | add // {}
' "$MP_SRC") || exit 1

# scope:user plugins whose marketplace (part after `@`) is a key of $1.
_target_plugins_for_mp() {
	jq -c --argjson mp "$1" '
        [(.plugins // {}) | to_entries[]
            | select(any(.value[]?; .scope == "user"))
            | .key
            | select($mp[(. | split("@") | last)] != null)
        ] | unique
    ' "$PL_SRC"
}
plugins_common=$(_target_plugins_for_mp "$target_common") || exit 1
plugins_private=$(_target_plugins_for_mp "$target_private") || exit 1

# Compact JSON of file $1, or default $2 when missing/empty/invalid.
_read_json_or() {
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

# --- diff helpers ---------------------------------------------------------
# Each prints drift lines to stdout and returns 1 when it found any.

_diff_marketplaces() {
	local current_file="$1" target="$2" current lines
	current=$(_read_json_or "$current_file" '{}')
	lines=$(jq -rn --argjson c "$current" --argjson t "$target" '
        [ ($t | to_entries[] | select($c[.key] == null) | "  + \(.key) (\(.value))"),
          ($c | to_entries[] | select($t[.key] == null) | "  - \(.key) (유령 — SSOT 에 없음)"),
          ($t | to_entries[] | select($c[.key] != null and $c[.key] != .value)
                             | "  ~ \(.key): \($c[.key]) -> \(.value)") ]
        | .[]
    ')
	[ -z "$lines" ] && return 0
	printf '%s\n' "$lines"
	return 1
}

_diff_plugins() {
	local current_file="$1" target="$2" current lines
	current=$(_read_json_or "$current_file" '{"plugins":[]}')
	lines=$(jq -rn --argjson c "$current" --argjson t "$target" '
        ($c.plugins // []) as $cur |
        [ ($t[]   | select(. as $x | ($cur | index($x)) | not) | "  + \(.)"),
          ($cur[] | select(. as $x | ($t   | index($x)) | not) | "  - \(.) (유령 — SSOT 에 없음)") ]
        | .[]
    ')
	[ -z "$lines" ] && return 0
	printf '%s\n' "$lines"
	return 1
}

# --- --check --------------------------------------------------------------

_run_check() {
	local drift=0 out

	echo "== 공용(github) 매니페스트 =="
	if ! out=$(_diff_marketplaces "$PUB_DIR/marketplaces.json" "$target_common"); then
		drift=1
		echo "marketplaces.json:"
		printf '%s\n' "$out"
	fi
	if ! out=$(_diff_plugins "$PUB_DIR/plugins.json" "$plugins_common"); then
		drift=1
		echo "plugins.json:"
		printf '%s\n' "$out"
	fi

	if [ "$COMPANY_ACTIVE" -eq 1 ]; then
		echo "== 사내(company) 매니페스트 =="
		if ! out=$(_diff_marketplaces "$PRIV_DIR/marketplaces.json" "$target_private"); then
			drift=1
			echo "company/marketplaces.json:"
			printf '%s\n' "$out"
		fi
		if ! out=$(_diff_plugins "$PRIV_DIR/plugins.json" "$plugins_private"); then
			drift=1
			echo "company/plugins.json:"
			printf '%s\n' "$out"
		fi
	else
		echo "(company/ 건너뜀 — 모드: ${MODE:-미설정})"
	fi

	if [ "$drift" -eq 0 ]; then
		echo "no drift — SSOT 와 매니페스트가 일치합니다."
		return 0
	fi
	echo "drift 감지 — 복구하려면: reconcile.sh --apply"
	return 1
}

# --- --apply --------------------------------------------------------------

# Write pretty (2-space) JSON to $1 only when the content actually differs,
# so an unchanged file keeps its mtime and never triggers a no-op commit.
_write_if_changed() {
	local target_file="$1" content="$2" tmp
	tmp="$target_file.tmp"
	printf '%s\n' "$content" >"$tmp" || return 1
	if [ -f "$target_file" ] && cmp -s "$tmp" "$target_file"; then
		rm -f "$tmp"
		return 0
	fi
	mv "$tmp" "$target_file"
}

# Stage + commit the given absolute paths in repo $1 only if they changed.
# Mirrors plugin-sync.sh's _commit_if_changed (ALLOW_MAIN_COMMIT escape hatch
# included) but takes absolute paths so it is independent of nesting depth.
_commit_if_changed() {
	local repo_dir="$1" msg="$2" f
	shift 2
	for f in "$@"; do
		if [ -f "$f" ]; then
			set -- "$@" "$f"
		fi
		shift
	done
	if [ "$#" -eq 0 ]; then
		return 0
	fi
	git -C "$repo_dir" add -- "$@" 2>/dev/null || return 0
	git -C "$repo_dir" diff --cached --quiet -- "$@" 2>/dev/null && return 0
	if ! ALLOW_MAIN_COMMIT=1 git -C "$repo_dir" commit -m "$msg" --quiet 2>/dev/null; then
		if git -C "$repo_dir" reset -q -- "$@" 2>/dev/null; then
			echo "reconcile: manifest commit failed in $repo_dir; changes left unstaged" >&2
		else
			echo "reconcile: manifest commit failed in $repo_dir; failed to unstage changes" >&2
		fi
	fi
}

_run_apply() {
	if [ -z "$MAIN_ROOT" ]; then
		echo "git 저장소를 찾을 수 없습니다 ($SCRIPT_DIR). dotfiles 안에서 실행하세요." >&2
		exit 1
	fi

	local mp_pretty pl_pretty
	mp_pretty=$(jq -n --argjson x "$target_common" '$x')
	pl_pretty=$(jq -n --argjson p "$plugins_common" '{plugins: $p}')
	_write_if_changed "$PUB_DIR/marketplaces.json" "$mp_pretty"
	_write_if_changed "$PUB_DIR/plugins.json" "$pl_pretty"
	_commit_if_changed "$MAIN_ROOT" "$SYNC_MSG" \
		"$PUB_DIR/marketplaces.json" "$PUB_DIR/plugins.json"

	if [ "$COMPANY_ACTIVE" -eq 1 ]; then
		mp_pretty=$(jq -n --argjson x "$target_private" '$x')
		pl_pretty=$(jq -n --argjson p "$plugins_private" '{plugins: $p}')
		_write_if_changed "$PRIV_DIR/marketplaces.json" "$mp_pretty"
		_write_if_changed "$PRIV_DIR/plugins.json" "$pl_pretty"
		_commit_if_changed "$PRIV_DIR" "$SYNC_MSG" \
			"$PRIV_DIR/marketplaces.json" "$PRIV_DIR/plugins.json"
	fi

	echo "apply 완료. 확인: reconcile.sh --check"
}

case "$MODE_ACTION" in
check) _run_check ;;
apply) _run_apply ;;
esac
