#!/usr/bin/env bash
# claude/plugin/reconcile.sh
#
# Full-recompute drift detector/repair for the dotfiles plugin manifests.
#
# claude/hooks/plugin-sync.sh keeps the manifests up to date INCREMENTALLY —
# it only patches them when it observes a `claude plugin ...` command. Any
# event it misses (crash, sync from another PC, a manual edit) leaves a ghost
# entry the hook can never remove, because there is no local event to key the
# delete off of.
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
#   --apply            rewrite the manifest to match SSOT
#
# Public (github) marketplaces route to claude/plugin/*.local.json — the
# gitignored machine-local overlay. The tracked claude/plugin/*.json pair is
# the upstream-owned registration contract this script only READS, to subtract
# its entries from the overlay target (#1685); writing an untracked overlay is
# also why the public scope makes no commit. Private (non-github) marketplaces
# route to claude/plugin/company/*.json, which is a separate private repo with
# no fork to diverge from and so still commits. company/ is processed only on
# an `internal` PC with the nested repo cloned.
#
# See docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load UX library for semantic log colors (#1114). Cosmetic only — colors
# are emitted only to an interactive TTY, so piped/redirected/automation
# runs stay byte-plain for grep/snapshot consumers (#1116); a missing lib
# also falls back to plain. ux_lib.sh self-disables on
# NO_COLOR / TERM=dumb / DOTFILES_TEST_MODE as well.
UX_LIB="$SCRIPT_DIR/../../shell-common/tools/ux_lib/ux_lib.sh"
if [ -t 1 ] && [ -r "$UX_LIB" ]; then
	# shellcheck source=../../shell-common/tools/ux_lib/ux_lib.sh
	source "$UX_LIB"
else
	UX_SUCCESS="" UX_ERROR="" UX_WARNING="" UX_MUTED="" UX_RESET=""
fi

# Color one `_diff_marketplaces`/`_diff_plugins` output line by its leading
# `+`/`-`/`~` marker (add/remove/change) — text itself is never altered.
_color_diff_line() {
	case "$1" in
	"  +"*) printf '%s%s%s\n' "$UX_SUCCESS" "$1" "$UX_RESET" ;;
	"  -"*) printf '%s%s%s\n' "$UX_ERROR" "$1" "$UX_RESET" ;;
	"  ~"*) printf '%s%s%s\n' "$UX_WARNING" "$1" "$UX_RESET" ;;
	*) printf '%s\n' "$1" ;;
	esac
}

MODE_ACTION="check"

_usage() {
	cat <<'EOF'
Usage: reconcile.sh [--check|--apply] [-h|--help]

  --check   (기본) SSOT(~/.claude-shared/plugins) 와 dotfiles 매니페스트의
            drift 를 표로 출력한다. drift 가 있으면 non-zero 로 종료한다.
  --apply   dotfiles 매니페스트를 SSOT 기준으로 재빌드한다 (유령 엔트리 제거
            포함). 커밋은 company/ 스코프에만 남는다 —
            "chore(claude-plugin): sync manifest".
  -h, --help  이 도움말 출력 후 종료.

SSOT: ~/.claude-shared/plugins/{known_marketplaces,installed_plugins}.json
      (CLAUDE_SHARED_PLUGINS_DIR 로 재정의 가능)
공용(github) → claude/plugin/*.local.json (gitignored 머신 로컬 오버레이, #1685).
      tracked claude/plugin/{marketplaces,plugins}.json 은 upstream 등록 계약이며
      이 스크립트가 절대 쓰지 않는다 — 계약에 있는 항목은 오버레이 목표에서 빠지고,
      이 PC 에 설치되지 않은 계약 항목도 유령으로 보고하지 않는다.
      계약에 새 플러그인을 등록하는 것은 upstream 의 명시적 PR 작업이다.
사내(non-github) → claude/plugin/company/*.json (별도 private 레포, 커밋 유지)
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
		echo "${UX_ERROR}알 수 없는 인자: $arg${UX_RESET}" >&2
		_usage >&2
		exit 2
		;;
	esac
done

command -v jq >/dev/null 2>&1 || {
	echo "${UX_ERROR}jq가 필요합니다.${UX_RESET}" >&2
	exit 1
}

# The commit-title helper (_plugin_sync_title) lives in shell-common so
# claude/hooks/plugin-sync.sh can reuse the identical format instead of
# growing a second copy (#1558).
# Resolved via $SHELL_COMMON rather than $SCRIPT_DIR because this script is
# also run from a copy that has no shell-common sibling (bats fixtures).
# Only --apply needs it, so the missing-helper check lives in _run_apply —
# --check must keep working on a half-installed tree.
# shellcheck disable=SC1091
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/plugin_sync_title.sh" 2>/dev/null || true
# The manifest reader (_claude_plugin_read_json_or) is the same helper the
# hook and restore.sh need, so it has a single home in shell-common (#1696).
# shellcheck disable=SC1091
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/claude_plugin_manifest.sh" 2>/dev/null || true

# Bootstrap fallback, NOT a second implementation to maintain in parallel.
# Unlike the commit title, the reader is on --check's path, and --check is
# required to work on a half-installed tree (the invariant stated above, pinned
# by tests/bats/tools/claude_plugin_reconcile.bats "--check still works when
# the ... helper cannot be sourced"). Degrading here would not fail loudly: an
# unread manifest looks exactly like an empty one, so drift would be reported
# backwards instead of being reported as an error. Behavior changes belong in
# shell-common/functions/claude_plugin_manifest.sh; this copy follows it.
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

# Same bootstrap-fallback contract for the tombstone prune (#1695 라운드2):
# --apply calls it, and this script must keep working on a half-installed tree.
if ! command -v _claude_plugin_tombstone_prune >/dev/null 2>&1; then
	_claude_plugin_tombstone_prune() {
		jq -cn --argjson old "$1" --argjson pl "$2" --argjson mp "$3" \
			'{marketplaces: (($old.marketplaces // []) - $mp),
			  plugins:      (($old.plugins // []) - $pl)}' 2>/dev/null
	}
fi

PUB_DIR="$SCRIPT_DIR"
PRIV_DIR="$SCRIPT_DIR/company"

# 공용 스코프의 쓰기 대상은 tracked 계약이 아니라 머신 로컬 오버레이다 (#1685).
# claude/plugin/{marketplaces,plugins}.json 은 upstream 이 소유하는 등록 계약이라
# 이 스크립트는 절대 쓰지 않고, 읽어서 오버레이 목표에서 빼기만 한다.
PUB_LOCAL_MP="$PUB_DIR/marketplaces.local.json"
PUB_LOCAL_PL="$PUB_DIR/plugins.local.json"
# "이 PC 에서 계약 항목을 uninstall 했다" 는 묘비 (#1695). --apply 는 다시
# 설치된 항목의 묘비만 지우고, 나머지는 건드리지 않는다.
PUB_TOMBSTONE="$PUB_DIR/removed.local.json"

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
		echo "${UX_ERROR}SSOT 파일이 없습니다: $f${UX_RESET}" >&2
		echo "${UX_ERROR}  → ~/.claude-shared/plugins 를 확인하거나 CLAUDE_SHARED_PLUGINS_DIR 를 설정하세요.${UX_RESET}" >&2
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

# --- 공용 오버레이 목표 = SSOT − tracked 등록 계약 (#1685) ------------------
# 계약에 이미 있는 항목을 목표에서 빼면 두 오판이 한꺼번에 사라진다:
#   1. 계약 항목이 오버레이에 중복 기록되는 것 (그러면 계약이 바뀔 때 로컬이 밀린다)
#   2. 이 PC 에 설치되지 않은 계약 항목이 "유령" 으로 보고되는 것 — fork 에서
#      upstream 이 등록만 해 둔 플러그인이 정확히 이 모양이다.
# 오버레이가 없고 계약이 곧 로컬 상태였던 기존 PC 에서는 목표가 비어 있으므로
# --apply 가 빈 오버레이를 쓸 뿐, 계약은 손대지 않는다.
overlay_common=$(jq -cn --argjson t "$target_common" \
	--argjson k "$(_claude_plugin_read_json_or "$PUB_DIR/marketplaces.json" '{}')" \
	'$t | with_entries(select($k[.key] == null))') || exit 1
overlay_plugins_common=$(jq -cn --argjson t "$plugins_common" \
	--argjson k "$(_claude_plugin_read_json_or "$PUB_DIR/plugins.json" '{"plugins":[]}')" \
	'$t - ($k.plugins // [])') || exit 1

# --- diff helpers ---------------------------------------------------------
# Each prints drift lines to stdout and returns 1 when it found any.

_diff_marketplaces() {
	local current_file="$1" target="$2" current lines
	current=$(_claude_plugin_read_json_or "$current_file" '{}')
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
	current=$(_claude_plugin_read_json_or "$current_file" '{"plugins":[]}')
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

	echo "${UX_MUTED}== 공용(github) 매니페스트 — 로컬 오버레이 ==${UX_RESET}"
	if ! out=$(_diff_marketplaces "$PUB_LOCAL_MP" "$overlay_common"); then
		drift=1
		echo "${UX_MUTED}marketplaces.local.json:${UX_RESET}"
		while IFS= read -r _line; do _color_diff_line "$_line"; done <<<"$out"
	fi
	if ! out=$(_diff_plugins "$PUB_LOCAL_PL" "$overlay_plugins_common"); then
		drift=1
		echo "${UX_MUTED}plugins.local.json:${UX_RESET}"
		while IFS= read -r _line; do _color_diff_line "$_line"; done <<<"$out"
	fi

	if [ "$COMPANY_ACTIVE" -eq 1 ]; then
		echo "${UX_MUTED}== 사내(company) 매니페스트 ==${UX_RESET}"
		if ! out=$(_diff_marketplaces "$PRIV_DIR/marketplaces.json" "$target_private"); then
			drift=1
			echo "${UX_MUTED}company/marketplaces.json:${UX_RESET}"
			while IFS= read -r _line; do _color_diff_line "$_line"; done <<<"$out"
		fi
		if ! out=$(_diff_plugins "$PRIV_DIR/plugins.json" "$plugins_private"); then
			drift=1
			echo "${UX_MUTED}company/plugins.json:${UX_RESET}"
			while IFS= read -r _line; do _color_diff_line "$_line"; done <<<"$out"
		fi
	else
		echo "${UX_MUTED}(company/ 건너뜀 — 모드: ${MODE:-미설정})${UX_RESET}"
	fi

	if [ "$drift" -eq 0 ]; then
		echo "${UX_SUCCESS}no drift — SSOT 와 매니페스트가 일치합니다.${UX_RESET}"
		return 0
	fi
	echo "${UX_ERROR}drift 감지 — 복구하려면: reconcile.sh --apply${UX_RESET}"
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
			echo "${UX_ERROR}reconcile: manifest commit failed in $repo_dir; changes left unstaged${UX_RESET}" >&2
		else
			echo "${UX_ERROR}reconcile: manifest commit failed in $repo_dir; failed to unstage changes${UX_RESET}" >&2
		fi
	fi
}

_run_apply() {
	# Commit titles come from the shell-common helper sourced at the top of
	# this script; without it --apply would commit under an empty subject.
	# Only the company/ scope still commits (#1685) — the public scope writes
	# an untracked overlay — so the guard is scoped to that branch.
	if [ "$COMPANY_ACTIVE" -eq 1 ] && ! command -v _plugin_sync_title >/dev/null 2>&1; then
		echo "${UX_ERROR}shell-common/functions/plugin_sync_title.sh 를 불러오지 못했습니다.${UX_RESET}" >&2
		echo "${UX_ERROR}  → dotfiles 설치를 확인하거나 SHELL_COMMON 을 설정하세요.${UX_RESET}" >&2
		exit 1
	fi

	local mp_pretty pl_pretty priv_title
	# 공용: gitignored 오버레이만 쓴다. tracked 등록 계약은 읽기 전용이고, 오버레이는
	# 추적되지 않으므로 커밋할 것 자체가 없다 — #1685 이전의
	# "chore(claude-plugin): sync manifest" 자동 커밋이 사라진 자리다.
	mp_pretty=$(jq -n --argjson x "$overlay_common" '$x')
	pl_pretty=$(jq -n --argjson p "$overlay_plugins_common" '{plugins: $p}')
	_write_if_changed "$PUB_LOCAL_MP" "$mp_pretty"
	_write_if_changed "$PUB_LOCAL_PL" "$pl_pretty"
	# 묘비 정리 (#1695): SSOT 가 "지금 설치돼 있다" 고 말하는 항목의 묘비는
	# 낡았다. 훅의 add 분기가 같은 일을 하지만 이 스크립트는 훅이 놓친 이벤트를
	# 메우는 자리이므로, 여기서도 한 번 맞춰 준다. 손대지 않은 묘비는 그대로다.
	if [ -f "$PUB_TOMBSTONE" ]; then
		# 차집합 규칙은 claude/hooks/plugin-sync.sh 와 공유한다 (#1695 라운드2
		# agy FOLLOW-UP) — 두 벌이면 "다시 설치됨" 의 정의가 갈린다.
		# `local` 은 필수다: 없으면 이 이름이 전역으로 샌다.
		local _tomb
		_tomb=$(_claude_plugin_tombstone_prune \
			"$(_claude_plugin_read_json_or "$PUB_TOMBSTONE" '{}')" \
			"$plugins_common" \
			"$(jq -cn --argjson m "$target_common" '$m | keys')")
		[ -n "$_tomb" ] && _write_if_changed "$PUB_TOMBSTONE" "$_tomb"
	fi

	if [ "$COMPANY_ACTIVE" -eq 1 ]; then
		priv_title=$(_plugin_sync_title "$SYNC_MSG" \
			"$PRIV_DIR/marketplaces.json" "$target_private" \
			"$PRIV_DIR/plugins.json" "$plugins_private")

		mp_pretty=$(jq -n --argjson x "$target_private" '$x')
		pl_pretty=$(jq -n --argjson p "$plugins_private" '{plugins: $p}')
		_write_if_changed "$PRIV_DIR/marketplaces.json" "$mp_pretty"
		_write_if_changed "$PRIV_DIR/plugins.json" "$pl_pretty"
		_commit_if_changed "$PRIV_DIR" "$priv_title" \
			"$PRIV_DIR/marketplaces.json" "$PRIV_DIR/plugins.json"
	fi

	echo "${UX_SUCCESS}apply 완료. 확인: reconcile.sh --check${UX_RESET}"
}

case "$MODE_ACTION" in
check) _run_check ;;
apply) _run_apply ;;
esac
