#!/bin/bash

# claude/setup.sh: Claude Code environment setup
#
# PURPOSE: Set up Claude Code configuration with symbolic links
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL INITIALIZATION (why this file is REQUIRED):
#   1. Creates ~/.claude/settings.json symlink (Claude Code settings)
#   2. Creates ~/.claude/settings.local.json symlink (env / per-user overrides)
#   3. Creates ~/.claude/statusline-command.sh symlink (status line script)
#   4. Creates ~/.claude/skills symlink (custom skills directory)
#   5. Creates ~/.claude/projects/GLOBAL/memory symlink (global memory)
#   6. Verifies ~/.claude directory structure
#
# These files/directories are version-controlled in dotfiles and should
# be managed via symbolic links for consistency across machines.
#
# See SETUP_GUIDE.md for more information

# --- Constants ---

# Initialize DOTFILES_ROOT
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"
CLAUDE_DOTFILES="${DOTFILES_ROOT}/claude"

# Home directory locations
HOME_CLAUDE="${HOME}/.claude"
HOME_SETTINGS="${HOME_CLAUDE}/settings.json"
HOME_STATUSLINE="${HOME_CLAUDE}/statusline-command.sh"
HOME_SKILLS="${HOME_CLAUDE}/skills"
HOME_DOCS="${HOME_CLAUDE}/docs"
HOME_GLOBAL_MEMORY="${HOME_CLAUDE}/projects/GLOBAL/memory"

# Dotfiles source locations
CLAUDE_SETTINGS_SOURCE="${CLAUDE_DOTFILES}/settings.json"
CLAUDE_STATUSLINE_SOURCE="${CLAUDE_DOTFILES}/statusline-command.sh"
CLAUDE_SKILLS_SOURCE="${CLAUDE_DOTFILES}/skills"
CLAUDE_DOCS_SOURCE="${CLAUDE_DOTFILES}/docs"
CLAUDE_GLOBAL_MEMORY_SOURCE="${CLAUDE_DOTFILES}/global-memory"

# Load UX library (unified library at shell-common/tools/ux_lib/)
UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    source "$UX_LIB"
else
    echo "Error: UX library not found at $UX_LIB"
    exit 1
fi

# Load mount utilities (provides _is_mounted)
MOUNT_LIB="${DOTFILES_ROOT}/shell-common/functions/mount.sh"
if [ -f "$MOUNT_LIB" ]; then
    source "$MOUNT_LIB"
else
    echo "Error: Mount library not found at $MOUNT_LIB"
    exit 1
fi

# --- Logging Compatibility Functions ---

log_info() { ux_info "$1"; }
log_error() { ux_error "$1"; }
log_critical() {
    ux_error "$1"
    exit 1
}
log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }
log_debug() { echo "${UX_MUTED}[DEBUG] $1${UX_RESET}"; }
log_warning() { ux_warning "$1"; }

log_error_and_exit() {
    log_critical "$1"
}

# --- Functions ---

# Auto-migrate legacy statusLine.command (issue #300, item A).
#
# PR #297 updated settings.template.json to point at the dotfiles SSOT path
# (${HOME}/dotfiles/claude/statusline-command.sh) but left the gitignored
# claude/settings.json copy untouched. Users on the multi-account layout
# whose live settings.json still hardcodes the legacy ${HOME}/.claude/...
# path silently lose the statusline because that file no longer exists
# under the empty guard directory.
#
# This helper detects that exact legacy literal and rewrites it in place
# (preserving any other field), with a timestamped backup. Any other
# value — user customisation, already-migrated, missing field — is left
# alone so the helper is fully idempotent.
_migrate_legacy_statusline_command() {
    local source_file="$CLAUDE_SETTINGS_SOURCE"
    # Literal ${HOME}; Claude Code expands it when reading settings.json.
    # shellcheck disable=SC2016
    local legacy_literal='${HOME}/.claude/statusline-command.sh'
    # shellcheck disable=SC2016
    local new_literal='${HOME}/dotfiles/claude/statusline-command.sh'

    [ -f "$source_file" ] || return 0
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq 미설치 — settings.json statusLine 자동 마이그레이션 건너뜀"
        log_warning "  ensure_jq 실행 후 setup.sh 재실행 권장"
        return 0
    fi

    local current
    # Null-safe (?) so a settings.json that omits .statusLine entirely or
    # has a non-object value there still falls through cleanly.
    current=$(jq -r '.statusLine?.command? // empty' "$source_file" 2>/dev/null)
    [ "$current" = "$legacy_literal" ] || return 0

    # 백업은 dotfiles tree 밖에 둔다 (issue #554). 과거 ${source_file}.* 로
    # 두면 settings.json 안의 평문 토큰(사내 ANTHROPIC_AUTH_TOKEN 등)이
    # untracked 파일로 노출돼 `git add -A` 1번에 push 될 위험이 있다.
    local backup_dir="${HOME}/.claude-backups"
    if ! mkdir -p "$backup_dir"; then
        log_error "백업 디렉토리 생성 실패: $backup_dir — 마이그레이션 중단"
        return 1
    fi
    local backup
    backup="${backup_dir}/settings.json.pre-statusline-fix-$(date +%Y%m%d%H%M%S)"
    if ! cp "$source_file" "$backup"; then
        log_error "settings.json 백업 실패: $backup — 마이그레이션 중단"
        return 1
    fi

    local tmp
    tmp=$(mktemp "${source_file}.XXXXXX") || {
        log_error "임시 파일 생성 실패 — 마이그레이션 중단"
        rm -f "$backup"
        return 1
    }

    if jq --arg new "$new_literal" '.statusLine.command = $new' \
            "$source_file" > "$tmp" && mv "$tmp" "$source_file"; then
        log_warning "settings.json statusLine.command 자동 마이그레이션 완료:"
        log_warning "  before: $legacy_literal"
        log_warning "  after:  $new_literal"
        log_warning "  backup: $backup"
    else
        rm -f "$tmp"
        log_error "settings.json 갱신 실패 — 백업 보존: $backup"
        return 1
    fi
}

# Auto-remove duplicate env block from settings.json (issue #555 follow-up,
# PR #557 review C1). The env SSOT moved to settings.local.json; users who
# previously hand-merged the env block into their per-machine settings.json
# would otherwise end up with duplicate definitions, defeating the SSOT
# intent. Idempotent — only mutates when both files carry an env block,
# always backs up, and restores on failure.
_migrate_remove_duplicate_env_from_settings() {
    local source_file="$CLAUDE_SETTINGS_SOURCE"
    local local_file="${CLAUDE_DOTFILES}/settings.local.json"

    [ -f "$source_file" ] || return 0
    [ -f "$local_file" ] || return 0
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq 미설치 — settings.json env 자동 마이그레이션 건너뜀"
        return 0
    fi

    # Skip when settings.json carries no env block.
    jq -e '.env? | type == "object"' "$source_file" >/dev/null 2>&1 || return 0
    # Skip when settings.local.json carries no env block (nothing to consolidate to).
    jq -e '.env? | type == "object"' "$local_file"  >/dev/null 2>&1 || return 0

    local backup
    backup="${source_file}.pre-env-migration-$(date +%Y%m%d%H%M%S)"
    if ! cp "$source_file" "$backup"; then
        log_warning "settings.json env 마이그레이션: 백업 실패 → skip"
        return 0
    fi

    local tmp
    tmp=$(mktemp "${source_file}.XXXXXX") || {
        log_warning "settings.json env 마이그레이션: 임시 파일 생성 실패 → skip"
        rm -f "$backup"
        return 0
    }

    if jq 'del(.env)' "$source_file" > "$tmp" && mv "$tmp" "$source_file"; then
        log_warning "settings.json: env 블록 제거됨 (SSOT 가 settings.local.json 으로 이동)"
        log_warning "  backup: $backup"
    else
        rm -f "$tmp"
        log_warning "settings.json env 마이그레이션 실패 — 원본 복원: $backup"
        mv "$backup" "$source_file"
    fi
}

# Auto-migrate legacy Claude Code plugin paths (issue #340).
#
# Claude Code recently moved its plugin storage from
# ${HOME}/.claude/plugins/... to ${HOME}/.claude-personal/plugins/... but
# pre-existing JSON state files still hold the old prefix. Symptoms:
#   - /doctor: 다수의 "Plugin <name> not found in marketplace" 경고
#   - /plugin: "Marketplace has corrupted installLocation ... expected a
#     path inside .claude-personal/plugins/marketplaces" 갱신 실패
#
# Fix: rewrite the prefix in two JSON state files in place. Idempotent —
# only acts when an old-prefix entry is present, otherwise no-op.
#
# Targets:
#   - ~/.claude-shared/plugins/known_marketplaces.json (top-level
#     <marketplace>.installLocation)
#   - ~/.claude-shared/plugins/installed_plugins.json
#     (.plugins[<key>][<idx>].installPath)
_migrate_legacy_plugin_paths() {
    local plugins_root="${HOME}/.claude-shared/plugins"
    local old_prefix="${HOME}/.claude/plugins/"
    local new_prefix="${HOME}/.claude-personal/plugins/"

    [ -d "$plugins_root" ] || return 0

    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq 미설치 — plugin 경로 자동 마이그레이션 건너뜀"
        return 0
    fi

    _migrate_one_plugin_json() {
        local file="$1"
        local stale_filter="$2"
        local rewrite_filter="$3"

        [ -f "$file" ] || return 0

        local stale_count
        stale_count=$(jq --arg old "$old_prefix" "$stale_filter" "$file" 2>/dev/null) || stale_count=0
        [ "${stale_count:-0}" -gt 0 ] || return 0

        local backup tmp
        backup="${file}.pre-plugin-path-fix-$(date +%Y%m%d%H%M%S)"
        if ! cp "$file" "$backup"; then
            log_error "$(basename "$file") 백업 실패: $backup — 마이그레이션 중단"
            return 1
        fi
        tmp=$(mktemp "${file}.XXXXXX") || {
            log_error "임시 파일 생성 실패 — 마이그레이션 중단"
            rm -f "$backup"
            return 1
        }

        if jq --arg old "$old_prefix" --arg new "$new_prefix" \
                "$rewrite_filter" "$file" > "$tmp" && mv "$tmp" "$file"; then
            log_warning "$(basename "$file") plugin 경로 마이그레이션: ${stale_count}건"
            log_warning "  backup: $backup"
        else
            rm -f "$tmp"
            log_error "$(basename "$file") 갱신 실패 — 백업 보존: $backup"
            return 1
        fi
    }

    # jq 변수 ($old/$new) 은 --arg 로 주입 — shell 변수 아님.
    # shellcheck disable=SC2016
    _migrate_one_plugin_json \
        "${plugins_root}/known_marketplaces.json" \
        '[.[] | select(.installLocation? | type == "string" and startswith($old))] | length' \
        'with_entries(
            if (.value.installLocation? | type) == "string"
               and (.value.installLocation | startswith($old))
            then .value.installLocation |= ($new + .[($old | length):])
            else . end
        )'

    # shellcheck disable=SC2016
    _migrate_one_plugin_json \
        "${plugins_root}/installed_plugins.json" \
        '[.plugins // {} | to_entries[] | .value[]? | select(.installPath? | type == "string" and startswith($old))] | length' \
        '.plugins |= with_entries(
            .value |= map(
                if (.installPath? | type) == "string"
                   and (.installPath | startswith($old))
                then .installPath |= ($new + .[($old | length):])
                else . end
            )
        )'

    unset -f _migrate_one_plugin_json
}

# Auto-install gh-issue-flow Stop hook into existing settings.json (issue #383).
#
# A new mechanical guard (`claude/hooks/gh_issue_flow_stop_guard.py`) blocks the
# model from ending its turn while a /gh-issue-flow chain is still mid-flight.
# settings.template.json already declares this hook for new installs, but the
# user-private claude/settings.json (gitignored) survives across template
# updates and would otherwise miss it.
#
# This helper rewrites .hooks.Stop in place, only when the exact entry is
# absent. Idempotent — present-with-same-command → no-op. Different command in
# .hooks.Stop is left alone (user customisation respected) and a warning is
# printed so the user can manually merge.
_migrate_install_gh_issue_flow_stop_hook() {
    local source_file="$CLAUDE_SETTINGS_SOURCE"
    # shellcheck disable=SC2016
    local hook_command='${HOME}/dotfiles/claude/hooks/gh_issue_flow_stop_guard.py'

    [ -f "$source_file" ] || return 0
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq 미설치 — gh-issue-flow Stop hook 자동 등록 건너뜀"
        return 0
    fi

    local current_count
    current_count=$(jq --arg cmd "$hook_command" \
        '[.hooks?.Stop?[]?.hooks?[]? | select(.command == $cmd)] | length' \
        "$source_file" 2>/dev/null) || current_count=0
    [ "${current_count:-0}" -eq 0 ] || return 0

    # If user already has *some* Stop hook entry, don't clobber — warn instead.
    local existing_stop
    existing_stop=$(jq '[.hooks?.Stop?[]?] | length' "$source_file" 2>/dev/null) || existing_stop=0
    if [ "${existing_stop:-0}" -gt 0 ]; then
        log_warning "settings.json 에 다른 Stop hook 이 이미 있습니다 — 자동 머지 생략."
        log_warning "  수동 추가 필요: claude/hooks/gh_issue_flow_stop_guard.py"
        log_warning "  참조: claude/skills/gh-issue-flow/references/stop-guard.md"
        return 0
    fi

    local backup tmp
    backup="${source_file}.pre-stop-hook-fix-$(date +%Y%m%d%H%M%S)"
    if ! cp "$source_file" "$backup"; then
        log_error "settings.json 백업 실패: $backup — 마이그레이션 중단"
        return 1
    fi
    tmp=$(mktemp "${source_file}.XXXXXX") || {
        log_error "임시 파일 생성 실패 — 마이그레이션 중단"
        rm -f "$backup"
        return 1
    }

    # jq 변수 ($cmd) 은 --arg 로 주입 — shell 변수 아님.
    # shellcheck disable=SC2016
    if jq --arg cmd "$hook_command" \
            '.hooks = ((.hooks // {}) | .Stop = ((.Stop // []) + [{"hooks":[{"type":"command","command":$cmd}]}]))' \
            "$source_file" > "$tmp" && mv "$tmp" "$source_file"; then
        log_warning "settings.json 에 gh-issue-flow Stop hook 자동 등록 완료"
        log_warning "  hook: $hook_command"
        log_warning "  backup: $backup"
    else
        rm -f "$tmp"
        log_error "settings.json 갱신 실패 — 백업 보존: $backup"
        return 1
    fi
}

# /sandbox 기능은 socat 을 요구하지만 sudo 가 필요한 install 이라
# 자동 처리하지 않고 경고만 노출 (issue #340).
_check_socat_for_sandbox() {
    if ! command -v socat >/dev/null 2>&1; then
        log_warning "socat 미설치 — /sandbox 사용 시 'sudo apt install -y socat' 필요"
    fi
}

_setup_bind_mount_sudoers() {
    local sudoers_file="$1"
    local description="$2"
    local source="$3"
    local target="$4"

    [ -d "$source" ] || return 0

    log_info "$description 디렉토리 bind mount sudoers 설정"
    if [ -f "$sudoers_file" ] && sudo grep -qF "$source" "$sudoers_file" 2>/dev/null; then
        log_dim "✓ sudoers 설정이 이미 존재합니다"
        return 0
    fi
    [ -f "$sudoers_file" ] && log_info "sudoers 경로가 변경되었습니다. 재생성합니다: $sudoers_file"

    if ! cat << EOF | sudo tee "$sudoers_file" > /dev/null
# Allow passwordless bind mount for Claude Code $description directory
# Created by dotfiles/claude/setup.sh
${USER} ALL=(ALL) NOPASSWD: /bin/mount --bind ${source} ${target}
${USER} ALL=(ALL) NOPASSWD: /usr/bin/mount --bind ${source} ${target}
${USER} ALL=(ALL) NOPASSWD: /bin/umount ${target}
${USER} ALL=(ALL) NOPASSWD: /usr/bin/umount ${target}
EOF
    then
        log_error "$description sudoers 파일 생성 실패"
        return 1
    fi

    if sudo chmod 440 "$sudoers_file"; then
        log_dim "✓ $description sudoers 설정 완료"
    else
        log_error "$description sudoers 파일 권한 설정 실패"
        return 1
    fi
}

# --- Main Script Logic (issue #287, Phase 1: multi-account) ---

log_debug "\n--- Claude Code dotfiles setup 시작 ---"

# settings.json 자동 부트스트랩 (issue #500, F-1).
# Fresh checkout (gitignored settings.json 부재) 에서도 hard-fail 없이
# 진행되도록 settings.template.json → settings.json 1회 복사. 멱등 —
# 이미 존재하면 no-op. 템플릿까지 부재한 비정상 상태는 아래 hard-fail
# 가드가 그대로 잡는다.
CLAUDE_SETTINGS_TEMPLATE="${CLAUDE_DOTFILES}/settings.template.json"
if [ ! -f "$CLAUDE_SETTINGS_SOURCE" ] && [ -f "$CLAUDE_SETTINGS_TEMPLATE" ]; then
    if cp "$CLAUDE_SETTINGS_TEMPLATE" "$CLAUDE_SETTINGS_SOURCE"; then
        log_warning "settings.json 자동 부트스트랩: settings.template.json → settings.json"
        log_warning "  필요 시 직접 편집하세요 (gitignored, PC-private)"
    else
        log_warning "settings.json 자동 부트스트랩 실패: cp 오류 — 수동 복사 필요"
    fi
fi

# 필수 dotfiles source 검증
[ -f "$CLAUDE_SETTINGS_SOURCE" ]      || log_error_and_exit "settings.json 없음: $CLAUDE_SETTINGS_SOURCE"
[ -f "$CLAUDE_STATUSLINE_SOURCE" ]    || log_error_and_exit "statusline-command.sh 없음: $CLAUDE_STATUSLINE_SOURCE"
[ -d "$CLAUDE_SKILLS_SOURCE" ]        || log_error_and_exit "skills 디렉토리 없음: $CLAUDE_SKILLS_SOURCE"
[ -d "$CLAUDE_DOCS_SOURCE" ]          || log_error_and_exit "docs 디렉토리 없음: $CLAUDE_DOCS_SOURCE"
[ -d "$CLAUDE_GLOBAL_MEMORY_SOURCE" ] || log_error_and_exit "global-memory 없음: $CLAUDE_GLOBAL_MEMORY_SOURCE"

# Auto-migrate legacy statusLine.command in claude/settings.json before any
# downstream symlink uses it (issue #300, item A). Idempotent — only acts
# on the exact PR #292 legacy literal, otherwise no-op.
_migrate_legacy_statusline_command

# Auto-remove duplicate env block from settings.json (issue #555 follow-up,
# PR #557 review C1). Idempotent — only acts when both settings.json and
# settings.local.json carry an env block, otherwise no-op.
_migrate_remove_duplicate_env_from_settings

# Auto-install gh-issue-flow Stop hook (issue #383). Idempotent — only adds
# the entry when it's missing AND no conflicting Stop hook is configured.
_migrate_install_gh_issue_flow_stop_hook

# 다중 계정 함수 source (env + integration).
# 두 파일은 함수 정의 앞에 단순 interactive guard(`case $- in *i*) ;; *)
# [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac`)를 가지므로,
# ./setup.sh 가 비대화형으로 호출됐을 때 함수 정의가 스킵된다.
# 결과적으로 _claude_has_unmigrated_data / _claude_resolve_account 가
# 미정의로 떨어져 다중 계정 루프(line 419)가 silent skip 됨 (issue #554).
# 가드 자체는 단순 형태를 유지해야 하므로(`bats/CI` 호환), source 직전
# prefix 형태로 FORCE_INIT 신호를 한 줄만 켠다.
DOTFILES_FORCE_INIT=1 . "$DOTFILES_ROOT/shell-common/env/claude.sh"
DOTFILES_FORCE_INIT=1 . "$DOTFILES_ROOT/shell-common/tools/integrations/claude.sh"

# 마이그레이션 미수행 가드는 mkdir 보다 먼저 — 그래야 stale ~/.claude 가
# 가드 디렉토리 생성으로 가려지지 않는다. SSOT: _claude_has_unmigrated_data
# (shell-common/tools/integrations/claude.sh)
if _claude_has_unmigrated_data; then
    log_warning "$HOME/.claude/ 에 기존 사용자 데이터가 있습니다."
    log_warning "쉘 재시작 후 다음 명령으로 마이그레이션하세요:"
    log_warning "  claude-accounts migrate"
    exit 0
fi

# 빈 ~/.claude/ 가드 디렉토리 + ~/.claude-shared/plugins
mkdir -p "$HOME/.claude"
mkdir -p "$HOME/.claude-shared/plugins"

# Claude Code plugin 경로 마이그레이션 (issue #340). 멱등 — 옛 prefix 가
# 남아있을 때만 갱신, 그 외 no-op. 백업은 timestamped 보존.
_migrate_legacy_plugin_paths

# /sandbox 의존성 점검 (issue #340).
_check_socat_for_sandbox

# 활성 계정 목록을 한 번만 조회하여 재사용 (PR #292 review 반영)
ENABLED_ACCOUNTS=$(_claude_resolve_account --list)

# 활성화된 계정마다 sudoers 등록 + setup
for acct in $ENABLED_ACCOUNTS; do
    cdir=$(_claude_resolve_account "$acct")
    log_info "Account: $acct → $cdir"

    if [ "${CLAUDE_SKIP_SUDOERS:-0}" != "1" ]; then
        _setup_bind_mount_sudoers \
            "/etc/sudoers.d/claude-skills-mount-${acct}" \
            "Skills (${acct})" \
            "$CLAUDE_SKILLS_SOURCE" \
            "${cdir}/skills"
        _setup_bind_mount_sudoers \
            "/etc/sudoers.d/claude-docs-mount-${acct}" \
            "Docs (${acct})" \
            "$CLAUDE_DOCS_SOURCE" \
            "${cdir}/docs"
    fi

    _claude_account_setup_one "$acct" "$cdir"
done

# --- Verify Links (모든 활성 계정) ---
log_debug "\n--- 심볼릭 링크 확인 ---"
for acct in $ENABLED_ACCOUNTS; do
    cdir=$(_claude_resolve_account "$acct")
    for link in settings.json settings.local.json statusline-command.sh plugins projects/GLOBAL/memory; do
        if [ -L "${cdir}/${link}" ]; then
            log_dim "✓ ${acct}/${link} 심볼릭 링크 확인됨"
        else
            log_error_and_exit "${acct}/${link} 심볼릭 링크 생성 실패"
        fi
    done
done

# --- Completion Messages ---
log_debug "--- Claude Code dotfiles setup 완료 ---"
echo ""
ux_success "Claude Code 다중 계정 설정 완료!"
ux_info "활성 계정: $(echo "$ENABLED_ACCOUNTS" | tr '\n' ' ')"
ux_info "Default: $CLAUDE_DEFAULT_ACCOUNT"
echo ""
ux_section "다음 단계"
ux_bullet "쉘 재시작 후 진단: ${UX_BOLD}claude-accounts status${UX_RESET}"
ux_bullet "처음 사용: ${UX_BOLD}claude-yolo${UX_RESET} (브라우저로 ${CLAUDE_DEFAULT_ACCOUNT} 로그인)"
ux_bullet "다른 계정: ${UX_BOLD}claude-yolo --user <name>${UX_RESET} 또는 ${UX_BOLD}claude-yolo-<name>${UX_RESET}"
echo ""

exit 0
