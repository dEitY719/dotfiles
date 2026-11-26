#!/usr/bin/env bash
# claude/plugin/register.sh — skills-register (#2443)
#
# Register, update or remove one internal (non-github.com) marketplace repo in
# the private company/ manifest pair from a single git URL, then publish it via
# publish-sync.sh (branch + PR + admin-merge). Installing is NOT done here: the
# next `skills-sync --restore` installs what the manifest now lists.
#
#   skills-register <git-url>                       add, or update an existing entry's URL
#   skills-register --remove <git-url|marketplace>  drop the marketplace and its plugins
#   skills-register --dry-run ...                   freshness check + JSON diff, no write
#
# The marketplace name and plugin list come from the repo's own
# .claude-plugin/marketplace.json (.name, .plugins[].name) — read from the
# workspace clone whose origin matches the URL, else from a scratch
# `git clone --depth 1`. The URL string is never parsed for a name.
#
# Only a new marketplace gets every plugin of its marketplace.json. Re-running
# for an existing one updates the URL alone: the *@<mp> selection in plugins.json
# is the user's, so unlisted repo plugins are only named (INFO) and listed ones
# the repo dropped are only warned about (#2455).
#
# An http(s) URL is stored with .git appended (claude reads a .git-less one as a
# raw marketplace.json), and a plugin name another marketplace already lists in
# any manifest is refused with an ignore-overlay hint (#2453).
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
CPM_LIB="${SHELL_COMMON:-$SCRIPT_DIR/../../shell-common}/lib/claude_plugin_manifest.sh"
# shellcheck source=../../shell-common/lib/gh_host.sh
[ -r "$GH_HOST_LIB" ] && . "$GH_HOST_LIB"
CF_LIB="${SHELL_COMMON:-$SCRIPT_DIR/../../shell-common}/lib/company_freshness.sh"

SYNC_MSG="chore(claude-plugin): sync manifest" # publish-sync.sh purity rule
COMPANY_DIR="$SCRIPT_DIR/company"
# publish-sync.sh publishes only $HOME/dotfiles's company/ (its MAIN_ROOT).
PUBLISH_PLUGIN_DIR="$HOME/dotfiles/claude/plugin"
WORKSPACE="${SKILLS_DIR:-${WORKSPACE_ROOT:-$HOME/para/project/skills}}"

_usage() {
	cat <<USAGE
Usage: skills-register [--dry-run] <git-url>
       skills-register [--dry-run] --remove <git-url|marketplace-name>

Add or update an internal (non-github.com) marketplace in
claude/plugin/company/{marketplaces,plugins}.json, commit it and publish it
via publish-sync.sh (PR + admin-merge). Install afterwards: skills-sync --restore

  --remove    Remove the marketplace key and every <plugin>@<marketplace> entry
  --dry-run   Check company/ freshness and print the JSON diff; no write, commit or PR
  -h, --help  Show this help
USAGE
}

# _norm_url <url> — comparable form: no trailing slash or .git.
_norm_url() {
	local u="${1%/}"
	printf '%s\n' "${u%.git}"
}

# _is_url <arg> — a git URL on a known transport (https/http/ssh/git/file, or
# scp-like user@host:path), never a bare name or a helper form like ext::.
_is_url() {
	case "$1" in
	https://* | http://* | ssh://* | git://* | file://*) return 0 ;;
	-*) return 1 ;;
	*@*:*)
		case "${1%%:*}" in */* | *" "*) return 1 ;; *@*) return 0 ;; esac
		;;
	esac
	return 1
}

# _has_credentials <url> — user:secret@ in the authority would be published
# verbatim (manifest, commit subject, PR), so it is refused.
_has_credentials() {
	local auth
	case "$1" in *://*) ;; *) return 1 ;; esac
	auth="${1#*://}"
	auth="${auth%%/*}"
	case "$auth" in *@*) ;; *) return 1 ;; esac
	case "${auth%@*}" in *:*) return 0 ;; esac
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
	if git clone --quiet --depth 1 -- "$url" "$tmp/repo" >/dev/null 2>&1; then
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
if _is_url "$target"; then
	if _has_credentials "$target"; then
		ux_error "URL 에 자격증명(user:secret@)이 있습니다 — 그대로 manifest/PR 에 게시되므로 거부합니다"
		exit 2
	fi
	_refuse_github_com "$target"
fi
# _claude_plugin_git_url (URL form) and _claude_plugin_name_owner (collision
# guard) are shared with update-skills.sh; the add path fails closed without
# them (#2453). --remove needs neither, so a broken lib never blocks cleanup.
if [ "$remove" = 0 ]; then
	# shellcheck source=../../shell-common/lib/claude_plugin_manifest.sh
	if ! . "$CPM_LIB" 2>/dev/null || ! command -v _claude_plugin_name_owner >/dev/null 2>&1; then
		ux_error "claude_plugin_manifest.sh 를 읽지 못했습니다 — URL 정규화·이름 충돌 검사 불가로 중단합니다: $CPM_LIB"
		exit 1
	fi
	# http(s) without .git is fetched as a raw marketplace.json by claude (#2453).
	_git_url=$(_claude_plugin_git_url "$target")
	if [ "$_git_url" != "$target" ]; then
		ux_info "https URL 끝에 .git 을 붙여 저장합니다: $_git_url"
		target="$_git_url"
	fi
fi
# From a worktree or other checkout the edit would land in a company/ that
# publish-sync.sh never publishes, so refuse instead of silently redirecting.
if [ "$(cd "$PUBLISH_PLUGIN_DIR" 2>/dev/null && pwd -P)" != "$(cd "$SCRIPT_DIR" && pwd -P)" ]; then
	ux_error "publish-sync.sh 는 $PUBLISH_PLUGIN_DIR/company 만 게시합니다 — ~/dotfiles 의 skills-register 로 실행하세요 (현재: $SCRIPT_DIR)"
	exit 2
fi
if [ ! -d "$COMPANY_DIR/.git" ]; then
	ux_error "company/ repo 가 없습니다 ($COMPANY_DIR) — 사내(internal) PC 에서만 등록할 수 있습니다"
	exit 1
fi
MANIFESTS=(marketplaces.json plugins.json)
# publish-sync.sh publishes the whole local file over origin/main, so editing a
# stale checkout would drop entries another PC registered since. --dry-run runs
# the same check so it predicts the real run (#2446).
# shellcheck source=../../shell-common/lib/company_freshness.sh
if ! . "$CF_LIB" 2>/dev/null || ! command -v _company_freshness >/dev/null 2>&1; then
	ux_error "company_freshness.sh 를 읽지 못했습니다 — 최신 상태 판별 불가로 중단합니다: $CF_LIB"
	exit 1
fi
if ! git -C "$COMPANY_DIR" fetch --quiet origin; then
	ux_error "company/ origin fetch 실패 — 최신 상태를 확인할 수 없어 중단합니다"
	exit 1
fi
_company_freshness "$COMPANY_DIR"
if [ "$CF_STATE" != fresh ]; then
	ux_error "$CF_MSG"
	if [ -n "$CF_FIX" ]; then ux_info "해결: $CF_FIX 후 다시 실행하세요"; fi
	exit 1
fi

_publish() {
	if ! "$SCRIPT_DIR/publish-sync.sh"; then
		ux_error "publish-sync.sh 실패 — 위 출력의 PR URL/안내를 확인하세요. PR 이 열려 있으면 병합 후 main 체크아웃 상태에서 git -C $COMPANY_DIR pull --rebase --autostash origin main 으로 로컬 main 을 정리하고, PR 이 없거나 닫혔으면 재실행하면 다시 게시합니다"
		exit 1
	fi
}

# _noop <msg> — nothing to change; still publish a commit an earlier run left
# unpublished (publish-sync failed), so a re-run is the retry.
_noop() {
	ux_info "$1"
	if [ "$dry_run" = 0 ] && ! git -C "$COMPANY_DIR" diff --quiet origin/main -- "${MANIFESTS[@]}"; then
		ux_warning "company/ 에 미게시 manifest 변경이 있어 publish-sync.sh 로 게시합니다"
		_publish
	fi
	exit 0
}

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
		_noop "등록돼 있지 않음 — 할 일 없음: $target"
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
	# An empty or malformed list would silently drop every registered plugin.
	if ! jq -e '(.plugins | type) == "array" and (.plugins | length) > 0
		and all(.plugins[]; (.name | type) == "string" and .name != "")' <<<"$manifest" >/dev/null 2>&1; then
		ux_error ".claude-plugin/marketplace.json 의 .plugins 가 비었거나 .name 이 없는 항목이 있습니다: $target"
		exit 1
	fi
	plugins=$(jq -c --arg mp "$mp" '[.plugins[].name | . + "@" + $mp]' <<<"$manifest") || exit 1
	existing=$(jq -r --arg k "$mp" 'has($k)' <<<"$mp_old")
	# The same plugin name from another marketplace would install its skills twice
	# (#2453). An update adds no plugin (#2455), so only a new entry is checked.
	[ "$existing" = true ] || while IFS= read -r _pname; do
		if _owner=$(_claude_plugin_name_owner "$_pname" "$mp" "$SCRIPT_DIR/plugins.json" \
			"$SCRIPT_DIR/plugins.local.json" "$COMPANY_DIR/plugins.json" "$COMPANY_DIR/plugins.local.json"); then
			ux_error "plugin 이름 충돌: $_pname@$mp — $_owner 이 이미 manifest 에 있습니다 (등록하지 않음)"
			ux_info "개발용 fork 라면 등록 대신 제외: claude/plugin/skills-workspace-ignore.local.json 에 \"$mp\" 추가"
			exit 2
		fi
	done < <(jq -r '.plugins[]?.name // empty' <<<"$manifest")
	# The stored raw string is compared as is, so an entry saved without .git
	# (or with a trailing slash) is rewritten by re-running with the same repo.
	mp_new=$(jq --arg k "$mp" --arg v "$target" '.[$k] = $v' <<<"$mp_old") || exit 1
	if [ "$existing" = true ]; then
		pl_new="$pl_old"
		# The selection spans company/plugins.json and its local overlay.
		_sel=$(jq -c '.plugins // []' <<<"$pl_old") || exit 1
		if _l=$(jq -c --argjson s "$_sel" '$s + (.plugins // [])' "$COMPANY_DIR/plugins.local.json" 2>/dev/null); then
			_sel="$_l"
		fi
		_unreg=$(jq -c --argjson h "$_sel" '[.[] | select(IN($h[]) | not) | sub("@[^@]*$"; "")]' <<<"$plugins") || exit 1
		if [ "$(jq length <<<"$_unreg")" -gt 0 ]; then
			ux_info "$mp 에 등록되지 않은 plugin $(jq length <<<"$_unreg")개가 있습니다 ($(jq -r 'join(", ")' <<<"$_unreg")) — 추가하지 않음 (필요하면 company/plugins.json 에 name@${mp} 를 직접 추가)"
		fi
		_gone=$(jq -r --arg mp "$mp" --argjson r "$plugins" \
			'[.[] | select(endswith("@" + $mp)) | select(IN($r[]) | not)] | join(", ")' <<<"$_sel") || exit 1
		if [ -n "$_gone" ]; then
			ux_warning "repo 에 없는 등록 plugin: $_gone — 제거하지 않음 (다음 skills-sync --restore 에서 install 이 실패할 수 있습니다)"
		fi
	else
		pl_new=$(jq --arg mp "$mp" --argjson p "$plugins" \
			'.plugins = ((.plugins // []) | map(select(endswith("@" + $mp) | not)) + $p | unique)' <<<"$pl_old") || exit 1
	fi
fi

# Sorted compare: the add path's `unique` re-sorts plugins, which alone is no change.
_canon() { jq -cS '.plugins |= ((. // []) | sort)' <<<"$1"; }
if [ "$(jq -cS . <<<"$mp_old")$(_canon "$pl_old")" = "$(jq -cS . <<<"$mp_new")$(_canon "$pl_new")" ]; then
	_noop "이미 등록됨 — 변경 없음: $mp"
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
if ! git -C "$COMPANY_DIR" add -- "${MANIFESTS[@]}" ||
	! ALLOW_MAIN_COMMIT=1 git -C "$COMPANY_DIR" commit --quiet -m "$SYNC_MSG ($target)" \
		-- "${MANIFESTS[@]}"; then
	ux_error "company/ 커밋 실패 — 파일은 수정된 채로 남았습니다: $COMPANY_DIR"
	exit 1
fi
ux_success "company/ 커밋: $SYNC_MSG ($target)"

_publish
if [ "$remove" = 1 ]; then
	ux_success "등록 해제 완료: $mp"
else
	ux_success "등록 완료: $mp"
	ux_info "설치: skills-sync --restore"
fi
