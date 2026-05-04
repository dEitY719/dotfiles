#!/bin/bash

# claude/setup.sh: Claude Code environment setup
#
# PURPOSE: Set up Claude Code configuration with symbolic links
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL INITIALIZATION (why this file is REQUIRED):
#   1. Creates ~/.claude/settings.json symlink (Claude Code settings)
#   2. Creates ~/.claude/statusline-command.sh symlink (status line script)
#   3. Creates ~/.claude/skills symlink (custom skills directory)
#   4. Creates ~/.claude/projects/GLOBAL/memory symlink (global memory)
#   5. Verifies ~/.claude directory structure
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
    current=$(jq -r '.statusLine.command // ""' "$source_file" 2>/dev/null)
    [ "$current" = "$legacy_literal" ] || return 0

    local backup
    backup="${source_file}.pre-statusline-fix-$(date +%Y%m%d%H%M%S)"
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

# 다중 계정 함수 source (env + integration)
. "$DOTFILES_ROOT/shell-common/env/claude.sh"
. "$DOTFILES_ROOT/shell-common/tools/integrations/claude.sh"

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
    for link in settings.json statusline-command.sh plugins projects/GLOBAL/memory; do
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
