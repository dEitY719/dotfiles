#!/usr/bin/env bash
# claude/plugin/restore.sh
#
# Reinstall Claude Code plugins/marketplaces from the dotfiles manifest.
# Public manifest (claude/plugin/{marketplaces,plugins}.json) is always
# restored. The private company/ nested repo is restored only when
# ~/.dotfiles-setup-mode == internal AND claude/plugin/company/.git exists
# (cloned there manually once — see the design doc).
#
# See docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

command -v jq >/dev/null 2>&1 || {
	echo "jq가 필요합니다." >&2
	exit 1
}
# --dry-run only prints the plan — don't require the claude CLI for that,
# so this also works as a preview before clinstall, and so CI (which has
# no claude binary) can exercise --dry-run in tests without it.
if [ "$DRY_RUN" -eq 0 ]; then
	command -v claude >/dev/null 2>&1 || {
		echo "claude CLI가 없습니다. 먼저 clinstall 하세요." >&2
		exit 1
	}
fi

_restore_from() {
	local mp_json="$1" pl_json="$2" label="$3" name repo plugin
	if [ ! -f "$mp_json" ] || [ ! -f "$pl_json" ]; then
		echo "  (${label} manifest 없음 — 건너뜀)"
		return 0
	fi
	echo "== ${label} marketplaces =="
	# `</dev/null` on the CLI calls: without it, `claude` reading stdin would
	# drain the `jq | while read` pipe and cut the loop short.
	jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$mp_json" |
		while IFS=$'\t' read -r name repo; do
			echo "  add: ${name} (${repo})"
			if [ "$DRY_RUN" -eq 0 ]; then
				claude plugin marketplace add "$repo" </dev/null || echo "    실패 — 계속 진행" >&2
			fi
		done
	echo "== ${label} plugins =="
	jq -r '.plugins[]' "$pl_json" |
		while read -r plugin; do
			echo "  install: ${plugin}"
			if [ "$DRY_RUN" -eq 0 ]; then
				claude plugin install "$plugin" </dev/null || echo "    실패 — 계속 진행" >&2
			fi
		done
}

_restore_from "$SCRIPT_DIR/marketplaces.json" "$SCRIPT_DIR/plugins.json" "공용"

MODE=$(cat "$HOME/.dotfiles-setup-mode" 2>/dev/null || echo "")
if [ "$MODE" = "internal" ]; then
	PRIV="$SCRIPT_DIR/company"
	if [ -d "$PRIV/.git" ]; then
		_restore_from "$PRIV/marketplaces.json" "$PRIV/plugins.json" "사내 전용"
	else
		echo "(사내 전용 레포 미설정 — 먼저 실행: git clone <GHES private repo url> $PRIV)"
	fi
else
	echo "(모드: ${MODE:-미설정} — 사내 전용 manifest는 internal에서만 복원)"
fi

echo "완료. 새 Claude Code 세션을 시작해 스킬이 로드됐는지 확인하세요."
