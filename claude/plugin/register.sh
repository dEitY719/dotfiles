#!/usr/bin/env bash
# claude/plugin/register.sh — skills-register (#2443)
#
# Register, update or remove one internal (non-github.com) marketplace repo in
# the private company/ manifest pair from a single git URL, then publish it via
# publish-sync.sh (branch + PR + admin-merge). Installing is NOT done here: the
# next `skills-sync --restore` installs what the manifest now lists.
#
#   skills-register <git-url>                       add, or update an existing entry
#   skills-register --remove <git-url|marketplace>  drop the marketplace and its plugins
#   skills-register --dry-run ...                   print the JSON diff only
#
# The marketplace name and plugin list come from the repo's own
# .claude-plugin/marketplace.json (.name, .plugins[].name) — read from the
# workspace clone whose origin matches the URL, else from a scratch
# `git clone --depth 1`. The URL string is never parsed for a name.
#
# Never edits the tracked claude/plugin/{marketplaces,plugins}.json: that pair
# is the upstream-owned registration contract (#1685), so a github.com URL is
# refused with a pointer to an upstream PR.
#
# Exit: 0 done / already registered, 1 failure, 2 usage error or refusal.
# Alias: skills-register (shell-common/aliases/skills_sync.sh)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UX_LIB="$SCRIPT_DIR/../../shell-common/tools/ux_lib/ux_lib.sh"
if [ -t 1 ] && [ -r "$UX_LIB" ]; then
	# shellcheck source=../../shell-common/tools/ux_lib/ux_lib.sh
	source "$UX_LIB"
else
	ux_success() { printf 'OK: %s\n' "$1"; }
	ux_error() { printf 'ERR: %s\n' "$1" >&2; }
	ux_warning() { printf 'WARN: %s\n' "$1"; }
	ux_info() { printf 'INFO: %s\n' "$1"; }
fi

# github.com matching lives only in lib/gh_host.sh (AGENTS.md Correction Rules).
GH_HOST_LIB="${SHELL_COMMON:-$SCRIPT_DIR/../../shell-common}/lib/gh_host.sh"
# shellcheck source=../../shell-common/lib/gh_host.sh
[ -r "$GH_HOST_LIB" ] && . "$GH_HOST_LIB"

SYNC_MSG="chore(claude-plugin): sync manifest" # publish-sync.sh purity rule
# Same company/ publish-sync.sh publishes (its MAIN_ROOT), never a worktree copy.
COMPANY_DIR="$HOME/dotfiles/claude/plugin/company"
WORKSPACE="${SKILLS_DIR:-${WORKSPACE_ROOT:-$HOME/para/project/skills}}"

_usage() {
	cat <<USAGE
Usage: skills-register [--dry-run] <git-url>
       skills-register [--dry-run] --remove <git-url|marketplace-name>

Add or update an internal (non-github.com) marketplace in
claude/plugin/company/{marketplaces,plugins}.json, commit it and publish it
via publish-sync.sh (PR + admin-merge). Install afterwards: skills-sync --restore

  --remove    Remove the marketplace key and every <plugin>@<marketplace> entry
  --dry-run   Print the JSON diff only; no write, commit or PR
  -h, --help  Show this help
USAGE
}

# _norm_url <url> — comparable form: no trailing slash or .git.
_norm_url() {
	local u="${1%/}"
	printf '%s\n' "${u%.git}"
}

# _is_url <arg> — a git URL (scheme://… or user@host:path), not a bare name.
_is_url() {
	case "$1" in *://* | *@*:*) return 0 ;; esac
	return 1
}

# _refuse_github_com <url> — exit 2 for github.com; fail closed without the predicate.
_refuse_github_com() {
	if ! command -v _gh_host_is_github_com >/dev/null 2>&1; then
		ux_error "lib/gh_host.sh 를 읽지 못했습니다 — host 판별 불가로 중단합니다: $GH_HOST_LIB"
		exit 1
	fi
	if _gh_host_is_github_com "$1"; then
		ux_error "github.com repo 는 공용 manifest(claude/plugin/{marketplaces,plugins}.json) 소관입니다"
		ux_info "upstream 에 PR 로 등록하세요 — skills-register 는 사내(GHES 등) repo 만 company/ 에 씁니다"
		exit 2
	fi
}

# _read_marketplace <url> — print the marketplace.json of the repo at <url>.
_read_marketplace() {
	local url="$1" want d o tmp out rc
	want=$(_norm_url "$url")
	for d in "$WORKSPACE"/*/; do
		[ -r "$d.claude-plugin/marketplace.json" ] || continue
		o=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
		if [ "$(_norm_url "$o")" = "$want" ]; then
			cat "$d.claude-plugin/marketplace.json"
			return
		fi
	done
	tmp=$(mktemp -d "${TMPDIR:-/tmp}/skills-register.XXXXXX") || return 1
	if git clone --quiet --depth 1 "$url" "$tmp/repo" >/dev/null 2>&1; then
		out=$(cat "$tmp/repo/.claude-plugin/marketplace.json" 2>/dev/null)
		rc=$?
	else
		ux_error "git clone 실패: $url"
		rc=1
	fi
	rm -rf "$tmp"
	[ "$rc" -eq 0 ] || return 1
	printf '%s\n' "$out"
}

dry_run=0
remove=0
target=""
for arg in "$@"; do
	case "$arg" in
	-h | --help | help)
		_usage
		exit 0
		;;
	--dry-run) dry_run=1 ;;
	--remove) remove=1 ;;
	-*)
		ux_error "알 수 없는 옵션: $arg"
		_usage >&2
		exit 2
		;;
	*)
		if [ -n "$target" ]; then
			ux_error "인자는 하나만 받습니다: $arg"
			exit 2
		fi
		target="$arg"
		;;
	esac
done
if [ -z "$target" ]; then
	_usage >&2
	exit 2
fi
if [ "$remove" = 0 ] && ! _is_url "$target"; then
	ux_error "git URL 이 아닙니다: $target (이름으로는 --remove 만 가능)"
	exit 2
fi

command -v jq >/dev/null 2>&1 || {
	ux_error "jq 가 필요합니다"
	exit 1
}
if _is_url "$target"; then _refuse_github_com "$target"; fi
if [ ! -d "$COMPANY_DIR/.git" ]; then
	ux_error "company/ repo 가 없습니다 ($COMPANY_DIR) — 사내(internal) PC 에서만 등록할 수 있습니다"
	exit 1
fi

MP_FILE="$COMPANY_DIR/marketplaces.json"
PL_FILE="$COMPANY_DIR/plugins.json"
mp_old=$(cat "$MP_FILE" 2>/dev/null)
pl_old=$(cat "$PL_FILE" 2>/dev/null)
[ -n "$mp_old" ] || mp_old='{}'
[ -n "$pl_old" ] || pl_old='{"plugins":[]}'

if [ "$remove" = 1 ]; then
	mp="$target"
	if _is_url "$target"; then
		mp=$(jq -r --arg u "$(_norm_url "$target")" \
			'to_entries[] | select((.value | tostring | sub("/$"; "") | sub("\\.git$"; "")) == $u) | .key' \
			<<<"$mp_old" | head -n 1)
	fi
	# A plugin entry left without its key still counts, so --remove can clean it up.
	if [ -z "$mp" ] || [ "$(jq -r --arg k "$mp" 'has($k)' <<<"$mp_old")$(jq -r --arg mp "$mp" \
		'any((.plugins // [])[]; endswith("@" + $mp))' <<<"$pl_old")" = falsefalse ]; then
		ux_info "등록돼 있지 않음 — 할 일 없음: $target"
		exit 0
	fi
	mp_new=$(jq --arg k "$mp" 'del(.[$k])' <<<"$mp_old") || exit 1
	pl_new=$(jq --arg mp "$mp" \
		'.plugins = ((.plugins // []) | map(select(endswith("@" + $mp) | not)))' <<<"$pl_old") || exit 1
else
	manifest=$(_read_marketplace "$target") || exit 1
	mp=$(jq -r '.name // empty' <<<"$manifest" 2>/dev/null)
	if [ -z "$mp" ]; then
		ux_error ".claude-plugin/marketplace.json 에 .name 이 없습니다: $target"
		exit 1
	fi
	plugins=$(jq -c --arg mp "$mp" '[.plugins[]?.name | select(. != null) | . + "@" + $mp]' <<<"$manifest") || exit 1
	mp_new=$(jq --arg k "$mp" --arg v "$target" '.[$k] = $v' <<<"$mp_old") || exit 1
	pl_new=$(jq --arg mp "$mp" --argjson p "$plugins" \
		'.plugins = ((.plugins // []) | map(select(endswith("@" + $mp) | not)) + $p | unique)' <<<"$pl_old") || exit 1
fi

# Sorted compare: the add path's `unique` re-sorts plugins, which alone is no change.
_canon() { jq -cS '.plugins |= ((. // []) | sort)' <<<"$1"; }
if [ "$(jq -cS . <<<"$mp_old")$(_canon "$pl_old")" = "$(jq -cS . <<<"$mp_new")$(_canon "$pl_new")" ]; then
	ux_info "이미 등록됨 — 변경 없음: $mp"
	exit 0
fi

if [ "$dry_run" = 1 ]; then
	diff -u --label "a/marketplaces.json" --label "b/marketplaces.json" <(jq . <<<"$mp_old") <(printf '%s\n' "$mp_new")
	diff -u --label "a/plugins.json" --label "b/plugins.json" <(jq . <<<"$pl_old") <(printf '%s\n' "$pl_new")
	ux_info "--dry-run: 파일·커밋·PR 변경 없음"
	exit 0
fi

printf '%s\n' "$mp_new" >"$MP_FILE.tmp" && mv "$MP_FILE.tmp" "$MP_FILE" || exit 1
printf '%s\n' "$pl_new" >"$PL_FILE.tmp" && mv "$PL_FILE.tmp" "$PL_FILE" || exit 1

# ALLOW_MAIN_COMMIT: same escape hatch claude/hooks/plugin-sync.sh uses on company/ main.
if ! git -C "$COMPANY_DIR" add -- marketplaces.json plugins.json ||
	! ALLOW_MAIN_COMMIT=1 git -C "$COMPANY_DIR" commit --quiet -m "$SYNC_MSG ($target)" \
		-- marketplaces.json plugins.json; then
	ux_error "company/ 커밋 실패 — 파일은 수정된 채로 남았습니다: $COMPANY_DIR"
	exit 1
fi
ux_success "company/ 커밋: $SYNC_MSG ($target)"

if ! "$SCRIPT_DIR/publish-sync.sh"; then
	ux_error "publish-sync.sh 실패 — 위 출력의 PR URL/원인을 확인하세요 (커밋은 company/ 로컬에 남음)"
	exit 1
fi
if [ "$remove" = 1 ]; then
	ux_success "등록 해제 완료: $mp"
else
	ux_success "등록 완료: $mp"
	ux_info "설치: skills-sync --restore"
fi
