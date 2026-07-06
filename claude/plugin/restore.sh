#!/usr/bin/env bash
# claude/plugin/restore.sh
#
# Reinstall Claude Code plugins/marketplaces from the dotfiles manifest.
# Public manifest (claude/plugin/{marketplaces,plugins}.json) is always
# restored. The private company/ nested repo is restored only when
# ~/.dotfiles-setup-mode == internal AND claude/plugin/company/.git exists
# (cloned there manually once — see the design doc).
#
# Default is add-only (backward compatible): SSOT items missing locally are
# added/installed, but surplus local items are left untouched. Pass --sync to
# also PRUNE local marketplaces/plugins that are absent from the SSOT, making
# the local set exactly match the manifest (two-way sync).
#
# TARGET CONFIG DIR (#1103): raw `claude` installs into ~/.claude when
# CLAUDE_CONFIG_DIR is unset. In public/external (multi-account) mode the
# interactive `claude` wrapper (claude_yolo) routes to ~/.claude-<account>,
# so a plain `restore.sh` used to install into the WRONG dir and silently
# no-op for the account actually in use. This script now resolves the same
# account-routed config dir(s) and injects CLAUDE_CONFIG_DIR before every
# `claude plugin` call. See _target_config_dirs below.
#
# See docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
SYNC=0
ALL_ACCOUNTS=0
USER_ACCOUNT=""

_usage() {
	cat <<'EOF'
Usage: restore.sh [--user <account>|--all-accounts] [--sync] [--dry-run] [-h|--help]

  (no flags)        add-only 복원 — SSOT 에 있으나 로컬에 없는 항목만 add/install (하위호환)
  --user <account>  이 계정의 config dir (~/.claude-<account>) 로 복원 (public/external 모드)
  --all-accounts    CLAUDE_ENABLED_ACCOUNTS 의 모든 계정 config dir 로 복원
  --sync            양방향 sync — 위에 더해, SSOT 에 없는 잉여 로컬 항목을 remove/uninstall
  --dry-run         실제 실행 없이 계획만 출력 (add + (--sync 시) prune 계획 모두)
  -h, --help        이 도움말 출력 후 종료

대상 config dir (#1103):
  - internal 모드 → ~/.claude (단일 계정)
  - 그 외 모드    → ~/.claude-<account> (기본: ${CLAUDE_DEFAULT_ACCOUNT:-personal})
  raw `claude` 는 CLAUDE_CONFIG_DIR 미설정 시 ~/.claude 로 설치되므로, 멀티계정
  모드에서 실사용 계정에 반영되도록 대상 dir 을 명시 주입한다.

잉여 정리 보호 장치:
  - source:directory 마켓플레이스(재현 불가한 머신 로컬)는 --sync 대상에서 제외
  - claude/plugin/.local-marketplaces.json (gitignored) 화이트리스트로 로컬
    수동 추가 항목 보호: {"marketplaces":["name",...],"plugins":["p@mp",...]}
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run) DRY_RUN=1 ;;
	--sync) SYNC=1 ;;
	--all-accounts) ALL_ACCOUNTS=1 ;;
	--user)
		shift
		[ $# -gt 0 ] || {
			echo "--user 다음에 계정 이름이 필요합니다." >&2
			_usage >&2
			exit 2
		}
		USER_ACCOUNT="$1"
		;;
	--user=*) USER_ACCOUNT="${1#--user=}" ;;
	-h | --help | help)
		_usage
		exit 0
		;;
	*)
		echo "알 수 없는 인자: $1" >&2
		_usage >&2
		exit 2
		;;
	esac
	shift
done

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

# --- setup-mode + company gating (computed once) --------------------------
MODE=$(cat "$HOME/.dotfiles-setup-mode" 2>/dev/null || echo "")
PRIV="$SCRIPT_DIR/company"
# COMPANY_ACTIVE gates BOTH the add pass and the --sync keep-set: the private
# manifest counts as SSOT (so its entries aren't pruned) only when it's a real,
# cloned repo on an internal PC. On external/public PCs it's out of scope and
# its entries are protected only by the directory-source rule / whitelist.
COMPANY_ACTIVE=0
if [ "$MODE" = "internal" ] && [ -d "$PRIV/.git" ]; then
	COMPANY_ACTIVE=1
fi

# _valid_acct <name> — POSIX safe-identifier check mirroring
# _claude_resolve_account (shell-common/tools/integrations/claude.sh:523):
# first char lowercase, rest [a-z0-9_-].
_valid_acct() {
	case "$1" in
	[a-z]*) ;;
	*) return 1 ;;
	esac
	case "$1" in
	*[!a-z0-9_-]*) return 1 ;;
	esac
	return 0
}

# _target_config_dirs — echo one target CLAUDE_CONFIG_DIR per line (#1103).
# Restore must install into the SAME dir the interactive `claude` wrapper
# (claude_yolo) uses, not the CLI default ~/.claude.
#   internal 모드              → ~/.claude
#   --all-accounts (그 외)     → 모든 CLAUDE_ENABLED_ACCOUNTS → ~/.claude-<a>
#   --user <a> / 기본 (그 외)  → ~/.claude-<account>
# Convention-based (~/.claude-<account>) mirrors _claude_resolve_account so a
# new account needs no code change here. Warnings go to stderr; only dir paths
# reach stdout so the caller can read them line by line.
_target_config_dirs() {
	if [ "$MODE" = "internal" ]; then
		echo "$HOME/.claude"
		return 0
	fi
	if [ "$ALL_ACCOUNTS" -eq 1 ]; then
		_tcd_n=0
		# shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
		for _tcd_a in ${CLAUDE_ENABLED_ACCOUNTS:-}; do
			_valid_acct "$_tcd_a" || continue
			echo "$HOME/.claude-$_tcd_a"
			_tcd_n=$((_tcd_n + 1))
		done
		if [ "$_tcd_n" -gt 0 ]; then
			return 0
		fi
		echo "경고: --all-accounts 이나 CLAUDE_ENABLED_ACCOUNTS 가 비어 있음 — 기본 계정으로 폴백" >&2
	fi
	_tcd_acct="${USER_ACCOUNT:-${CLAUDE_DEFAULT_ACCOUNT:-personal}}"
	if _valid_acct "$_tcd_acct"; then
		echo "$HOME/.claude-$_tcd_acct"
		return 0
	fi
	echo "경고: 계정 이름 '$_tcd_acct' 이 유효하지 않음 — ~/.claude 로 폴백 (#1103 주의)" >&2
	echo "$HOME/.claude"
	return 0
}

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

# --- --sync prune pass helpers --------------------------------------------
# Keep-sets: names/ids that must NOT be pruned. Union of every in-scope SSOT
# manifest plus the local whitelist. Using the union (not per-manifest
# ownership) is what stops the public pass from mistaking a company-only entry
# for surplus — the design's chosen resolution.
_keep_marketplaces() {
	jq -r 'keys[]' "$SCRIPT_DIR/marketplaces.json" 2>/dev/null
	[ "$COMPANY_ACTIVE" -eq 1 ] && [ -f "$PRIV/marketplaces.json" ] &&
		jq -r 'keys[]' "$PRIV/marketplaces.json" 2>/dev/null
	[ -f "$WHITELIST" ] && jq -r '(.marketplaces // [])[]' "$WHITELIST" 2>/dev/null
	return 0
}
_keep_plugins() {
	jq -r '(.plugins // [])[]' "$SCRIPT_DIR/plugins.json" 2>/dev/null
	[ "$COMPANY_ACTIVE" -eq 1 ] && [ -f "$PRIV/plugins.json" ] &&
		jq -r '(.plugins // [])[]' "$PRIV/plugins.json" 2>/dev/null
	[ -f "$WHITELIST" ] && jq -r '(.plugins // [])[]' "$WHITELIST" 2>/dev/null
	return 0
}

# Local marketplaces eligible for pruning: every known marketplace EXCEPT
# source:directory ones (machine-local, non-reproducible — a Non-Goal to track,
# so never a prune candidate either).
_local_marketplaces() {
	[ -f "$MP_LOCAL" ] || return 0
	jq -r 'to_entries[] | select(.value.source.source != "directory") | .key' \
		"$MP_LOCAL" 2>/dev/null
	return 0
}
# Local prune-eligible plugins: scope:user only, excluding any whose marketplace
# is directory-sourced. Mirrors exactly what the hook records into the manifest,
# so the two never disagree on what's in scope.
_local_plugins() {
	[ -f "$PL_LOCAL" ] || return 0
	local mp_src
	mp_src=$(jq -c '.' "$MP_LOCAL" 2>/dev/null)
	[ -n "$mp_src" ] || mp_src='{}'
	jq -r --argjson m "$mp_src" '
        (.plugins // {}) | to_entries[]
        | select(any(.value[]?; .scope == "user"))
        | .key
        | select(($m[(. | split("@") | last)] | .source?.source? // "") != "directory")
    ' "$PL_LOCAL" 2>/dev/null
	return 0
}

# _prune_pass — the --sync surplus removal, scoped to the current
# CLAUDE_CONFIG_DIR. Local ground truth defaults to the TARGET account's own
# plugins/ dir (so a per-account restore prunes against that account's real
# state), overridable via CLAUDE_SHARED_PLUGINS_DIR (tests point this at a
# fixture). SHARED_DIR/MP_LOCAL/PL_LOCAL/WHITELIST are intentionally global so
# the _keep_*/_local_* helpers above resolve them.
_prune_pass() {
	SHARED_DIR="${CLAUDE_SHARED_PLUGINS_DIR:-$CLAUDE_CONFIG_DIR/plugins}"
	MP_LOCAL="$SHARED_DIR/known_marketplaces.json"
	PL_LOCAL="$SHARED_DIR/installed_plugins.json"
	WHITELIST="$SCRIPT_DIR/.local-marketplaces.json"

	echo "== sync: 잉여 항목 정리 (SSOT 에 없는 로컬 항목) =="
	local surplus_pl surplus_mp
	surplus_pl=$(comm -23 <(_local_plugins | sort -u) <(_keep_plugins | sort -u))
	surplus_mp=$(comm -23 <(_local_marketplaces | sort -u) <(_keep_marketplaces | sort -u))

	if [ -z "$surplus_pl" ] && [ -z "$surplus_mp" ]; then
		echo "  (제거할 잉여 항목 없음 — SSOT 와 로컬이 일치)"
	fi

	# Uninstall plugins BEFORE removing their marketplaces so a plugin is never
	# orphaned by its marketplace disappearing first.
	printf '%s\n' "$surplus_pl" |
		while read -r plugin; do
			[ -n "$plugin" ] || continue
			echo "  uninstall: ${plugin}"
			if [ "$DRY_RUN" -eq 0 ]; then
				claude plugin uninstall "$plugin" </dev/null || echo "    실패 — 계속 진행" >&2
			fi
		done
	printf '%s\n' "$surplus_mp" |
		while read -r name; do
			[ -n "$name" ] || continue
			echo "  remove: ${name}"
			if [ "$DRY_RUN" -eq 0 ]; then
				claude plugin marketplace remove "$name" </dev/null || echo "    실패 — 계속 진행" >&2
			fi
		done
}

# _run_for_config_dir — one full restore against the exported CLAUDE_CONFIG_DIR.
_run_for_config_dir() {
	echo "== 대상 config dir: ${CLAUDE_CONFIG_DIR} =="
	if [ "$DRY_RUN" -eq 0 ] && [ ! -d "$CLAUDE_CONFIG_DIR" ]; then
		echo "  (참고: 대상 dir 없음 — claude CLI 가 첫 실행 시 생성)"
	fi

	_restore_from "$SCRIPT_DIR/marketplaces.json" "$SCRIPT_DIR/plugins.json" "공용"

	if [ "$MODE" = "internal" ]; then
		if [ "$COMPANY_ACTIVE" -eq 1 ]; then
			_restore_from "$PRIV/marketplaces.json" "$PRIV/plugins.json" "사내 전용"
		else
			echo "(사내 전용 레포 미설정 — 먼저 실행: git clone <GHES private repo url> $PRIV)"
		fi
	else
		echo "(모드: ${MODE:-미설정} — 사내 전용 manifest는 internal에서만 복원)"
	fi

	if [ "$SYNC" -eq 1 ]; then
		_prune_pass
	fi
}

# --- driver: restore into each account-routed config dir ------------------
while IFS= read -r _cfg; do
	[ -n "$_cfg" ] || continue
	export CLAUDE_CONFIG_DIR="$_cfg"
	_run_for_config_dir
done < <(_target_config_dirs)

echo "완료. 새 Claude Code 세션을 시작해 스킬이 로드됐는지 확인하세요."
