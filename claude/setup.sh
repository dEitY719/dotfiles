#!/bin/bash

# claude/setup.sh: Claude Code environment setup
#
# PURPOSE: Set up Claude Code configuration with symbolic links
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL INITIALIZATION (why this file is REQUIRED):
#   1. Creates ~/.claude/settings.json symlink (tracked SSOT, #584)
#   2. Creates ~/.claude/statusline-command.sh symlink (status line script)
#   3. Creates ~/.claude/skills symlink (custom skills directory)
#   4. Creates ~/.claude/docs symlink (custom docs directory)
#   5. Creates ~/.claude/projects/GLOBAL/memory symlink (global memory)
#   6. Verifies ~/.claude directory structure
#
# Internal mode 에서 ~/.claude/settings.json 은 aws/setup.sh 가 dotfiles
# SSOT (claude/settings.json) + Bedrock 오버레이
# (claude/settings.bedrock-overlay.example) 를 jq deep-merge 한 결과
# 실파일로 시드한다 (#687, 이전 #677 F-7 의 settings.local.json 분리 디자인
# 폐기). 본 스크립트는 internal 분기에서 settings.json symlink 를
# 만들지 않는다. ~/.claude/settings.local.json 은 #683 F-2 이후 본 스크립트가
# 생성하지 않으며, #687 이후엔 aws/setup.sh 도 만들지 않고 잔존 시 안내만 한다.
#
# These files/directories are version-controlled in dotfiles and should
# be managed via symbolic links for consistency across machines.
#
# See SETUP_GUIDE.md for more information

# --- Constants ---

# Initialize DOTFILES_ROOT
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

# Canonicalize to the main worktree (issue #589). When invoked from a
# linked worktree, the script path resolves to <worktree>/claude/setup.sh
# and DOTFILES_ROOT becomes the worktree — that path would then be baked
# into every ~/.claude-*/ symlink we create below. Falling through to the
# worktree path is acceptable if the helper is missing (no regression).
_CLAUDE_DOTFILES_RESOLVER="${DOTFILES_ROOT}/shell-common/functions/dotfiles_root.sh"
if [ -r "$_CLAUDE_DOTFILES_RESOLVER" ]; then
    # shellcheck source=../shell-common/functions/dotfiles_root.sh
    source "$_CLAUDE_DOTFILES_RESOLVER"
    _CLAUDE_CANONICAL=$(_resolve_dotfiles_root_canonical "$DOTFILES_ROOT")
    if [ -n "$_CLAUDE_CANONICAL" ] && [ "$_CLAUDE_CANONICAL" != "$DOTFILES_ROOT" ]; then
        echo "[claude/setup.sh] 워크트리 감지 — 메인 워크트리로 전환: $_CLAUDE_CANONICAL" >&2
        DOTFILES_ROOT="$_CLAUDE_CANONICAL"
    fi
    unset _CLAUDE_CANONICAL
fi
unset _CLAUDE_DOTFILES_RESOLVER

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

# Load mount utilities (provides _is_mounted).
#
# shell-common/functions/mount.sh has the standard interactive guard:
#   case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# setup.sh is normally invoked non-interactively, so force the function
# definitions to load here just like the claude env/integration sources below.
MOUNT_LIB="${DOTFILES_ROOT}/shell-common/functions/mount.sh"
if [ -f "$MOUNT_LIB" ]; then
    DOTFILES_FORCE_INIT=1 . "$MOUNT_LIB"
else
    log_error_and_exit "Mount library not found at $MOUNT_LIB"
fi

if ! declare -f _is_mounted >/dev/null 2>&1; then
    log_error_and_exit "Mount library did not define _is_mounted: $MOUNT_LIB"
fi

# --- Functions ---

# Auto-migrate legacy statusLine.command (issue #300, item A).
#
# Now that claude/settings.json is the tracked SSOT (#584), this migration
# is a defense-in-depth no-op for the canonical install — the SSOT already
# carries the correct ${HOME}/dotfiles/claude/statusline-command.sh path.
# It is left in place for installs whose live ~/.claude/settings.json was
# carried over from a pre-#584 multi-account layout and still hardcodes
# the legacy ${HOME}/.claude/... path.
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

# Resolve the currently active Claude Code config directory used as the
# canonical prefix for plugin state migration.
#
# Detection order (issue: multi-account installLocation prefix mismatch):
#   1. $CLAUDE_CONFIG_DIR if set (Claude Code's own override)
#   2. $HOME/.claude — only when _dotfiles_setup_mode says we are in
#      `internal` (single-account) mode. In multi-account mode the
#      script later (~L578) creates ~/.claude as an empty guard dir, so
#      a bare `[ -d ~/.claude ]` filesystem test would falsely succeed
#      and the migration would normalize prefixes to the guard path.
#      Gate by the SSOT mode helper instead.
#   3. $HOME/.claude-personal (multi-account default — backward compat
#      with the original #340 migration target)
#
# Prints the absolute dir on stdout (no trailing slash). Never fails.
_current_claude_config_dir() {
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        printf '%s' "${CLAUDE_CONFIG_DIR%/}"
        return 0
    fi
    if command -v _dotfiles_setup_mode >/dev/null 2>&1 \
       && [ "$(_dotfiles_setup_mode)" = "internal" ]; then
        printf '%s' "${HOME}/.claude"
        return 0
    fi
    printf '%s' "${HOME}/.claude-personal"
}

# Auto-migrate stale Claude Code plugin paths (issue #340 + multi-account
# follow-up).
#
# Claude Code persists absolute paths into two JSON state files. When the
# user switches between accounts (.claude-personal / .claude-work /
# .claude-work1 / ...) those paths can point at a different account dir
# than the currently-active one, even though every account's plugins/
# symlinks into ~/.claude-shared/plugins/ (so the underlying data is the
# same). Symptoms:
#   - /doctor: 다수의 "Plugin <name> not found in marketplace" 경고
#   - /plugin: "Marketplace has corrupted installLocation ... expected a
#     path inside <current account>/plugins/marketplaces" 갱신 실패
#
# Fix: rewrite ANY ${HOME}/.claude(-<suffix>)?/plugins/ prefix in two JSON
# state files to the currently-active config dir's plugins/ prefix.
# Idempotent — entries already at the canonical prefix are left alone.
#
# Targets:
#   - ~/.claude-shared/plugins/known_marketplaces.json (top-level
#     <marketplace>.installLocation)
#   - ~/.claude-shared/plugins/installed_plugins.json
#     (.plugins[<key>][<idx>].installPath)
_migrate_legacy_plugin_paths() {
    local plugins_root="${HOME}/.claude-shared/plugins"
    local new_prefix
    new_prefix="$(_current_claude_config_dir)/plugins/"
    # Match any ${HOME}/.claude(-suffix)?/plugins/ — the legacy ${HOME}/.claude/
    # form from #340 plus every per-account variant. $HOME is interpolated
    # literally (not as a regex), so an unusual $HOME containing regex
    # meta-chars would over-match; acceptable for our environment.
    local old_regex="^${HOME}/\\.claude(-[A-Za-z0-9_]+)?/plugins/"

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
        stale_count=$(jq --arg re "$old_regex" --arg new "$new_prefix" \
            "$stale_filter" "$file" 2>/dev/null) || stale_count=0
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

        if jq --arg re "$old_regex" --arg new "$new_prefix" \
                "$rewrite_filter" "$file" > "$tmp" && mv "$tmp" "$file"; then
            log_warning "$(basename "$file") plugin 경로 마이그레이션: ${stale_count}건 → ${new_prefix}"
            log_warning "  backup: $backup"
        else
            rm -f "$tmp"
            log_error "$(basename "$file") 갱신 실패 — 백업 보존: $backup"
            return 1
        fi
    }

    # jq 변수 ($re/$new) 은 --arg 로 주입 — shell 변수 아님.
    # "stale" = matches the legacy regex AND is not already at $new.
    # shellcheck disable=SC2016
    _migrate_one_plugin_json \
        "${plugins_root}/known_marketplaces.json" \
        '[.[] | select(
            .installLocation? | type == "string"
            and test($re)
            and (startswith($new) | not)
        )] | length' \
        'with_entries(
            if (.value.installLocation? | type) == "string"
               and (.value.installLocation | test($re))
               and ((.value.installLocation | startswith($new)) | not)
            then .value.installLocation |= sub($re; $new)
            else . end
        )'

    # shellcheck disable=SC2016
    _migrate_one_plugin_json \
        "${plugins_root}/installed_plugins.json" \
        '[.plugins // {} | to_entries[] | .value[]? | select(
            .installPath? | type == "string"
            and test($re)
            and (startswith($new) | not)
        )] | length' \
        '.plugins |= with_entries(
            .value |= map(
                if (.installPath? | type) == "string"
                   and (.installPath | test($re))
                   and ((.installPath | startswith($new)) | not)
                then .installPath |= sub($re; $new)
                else . end
            )
        )'

    unset -f _migrate_one_plugin_json
}

# Auto-install gh-issue-flow Stop hook into existing settings.json (issue #383).
#
# Now that claude/settings.json is the tracked SSOT (#584), this migration
# is a defense-in-depth no-op for the canonical install — the SSOT already
# declares the Stop hook. It still guards pre-#584 installs whose live
# settings.json was carried over without the hook entry.
#
# Rewrites .hooks.Stop in place only when the exact entry is absent.
# Idempotent — present-with-same-command → no-op. Different command in
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

# Auto-link ~/.gemini/skills → claude/skills SSOT when Gemini CLI is installed
# (issue #562). Idempotent — correct symlink → no-op; real directory →
# timestamped backup + symlink; wrong-target symlink → replace.
_setup_gemini_skills_symlink() {
    local gemini_home="${HOME}/.gemini"
    local target="${gemini_home}/skills"

    [ -d "$gemini_home" ] || return 0

    if [ -L "$target" ]; then
        local current
        current="$(readlink -f "$target" 2>/dev/null)"
        if [ "$current" = "$(readlink -f "$CLAUDE_SKILLS_SOURCE")" ]; then
            log_dim "✓ ${HOME}/.gemini/skills SSOT symlink 이미 연결됨"
            return 0
        fi
        log_warning "${HOME}/.gemini/skills symlink 대상이 다름 — 교체"
        rm -f "$target"
    elif [ -e "$target" ] || [ -L "$target" ]; then
        local backup
        backup="${target}-$(date +%Y%m%d%H%M%S)-backup"
        log_warning "${HOME}/.gemini/skills 기존 항목 백업: $backup"
        mv "$target" "$backup" || {
            log_error "${HOME}/.gemini/skills 백업 실패 — skip"
            return 1
        }
    fi

    log_info "${HOME}/.gemini/skills → $CLAUDE_SKILLS_SOURCE symlink 생성"
    ln -s "$CLAUDE_SKILLS_SOURCE" "$target" \
        || { log_error "${HOME}/.gemini/skills symlink 생성 실패"; return 1; }
    log_dim "✓ ${HOME}/.gemini/skills SSOT 연결 완료"
}

# _print_stale_bind_mount_sudoers_hint — surface stale /etc/sudoers.d/
# files left over from the pre-#575 bind-mount design.
#
# Issue #575 removed _setup_bind_mount_sudoers and the entire bind-mount
# integration in favour of directory-level symlinks. Existing PCs may
# still carry sudoers entries from the prior layout — they no longer
# match anything in the setup and only widen the sudoers surface, so
# point the user at them. Cleanup is left manual on purpose because
# rm under /etc/sudoers.d/ needs sudo and we don't want to prompt
# from setup.sh.
_print_stale_bind_mount_sudoers_hint() {
    local sudoers_glob='/etc/sudoers.d/claude-skills-mount-* /etc/sudoers.d/claude-docs-mount-*'
    local found=""
    # shellcheck disable=SC2086  # glob intentionally unquoted
    for _f in $sudoers_glob; do
        [ -f "$_f" ] || continue
        found="${found}  $_f
"
    done

    [ -n "$found" ] || return 0

    echo ""
    ux_section "Stale bind-mount sudoers (issue #575)"
    ux_info "Issue #575 retired bind-mount for Claude skills/docs in favour of"
    ux_info "a single directory symlink. The sudoers files below were created"
    ux_info "by an earlier dotfiles version and no longer have a matching"
    ux_info "consumer — they only widen the sudoers surface. Remove them"
    ux_info "manually when convenient (requires sudo):"
    echo ""
    printf '%s' "$found"
    echo ""
    ux_bullet "Quick command:"
    cat <<'EOF'

    sudo rm -f /etc/sudoers.d/claude-skills-mount-* \
               /etc/sudoers.d/claude-docs-mount-*

EOF
}

# Note: 이전에 있던 `_print_internal_local_env_guidance` 는 #683 F-2 에서 제거.
# 사내 PC 의 settings 는 `aws/setup.sh` 가 dotfiles SSOT (claude/settings.json)
# + Bedrock 오버레이 (claude/settings.bedrock-overlay.example) 를 jq deep-merge
# 해 ~/.claude/settings.json 실파일로 작성한다 (#687, 이전 #677 F-7 의
# settings.local.json 분리 디자인 폐기).
#
# 함께 deprecate 된 env 키 (게이트웨이 path 전용, Bedrock 와 양립 불가 — #677 O-1):
#   - ANTHROPIC_BASE_URL  (was: http://cloud.dtgpt.samsungds.net/llm)
#   - ANTHROPIC_AUTH_TOKEN (was: placeholder "your-dt-api-key")
#   - ANTHROPIC_MODEL      (was: "Qwen3.6-27B")
# 위 3 키는 더 이상 주입되지 않으며, ~/.claude/settings.json 에 잔존해도
# aws/setup.sh 가 머지 중 자동 strip 한다.

# --- Main Script Logic (issue #287, Phase 1: multi-account) ---

log_debug "\n--- Claude Code dotfiles setup 시작 ---"

# 필수 dotfiles source 검증
# settings.json 은 이제 tracked SSOT (#584) — 부트스트랩/템플릿 단계 불필요.
[ -f "$CLAUDE_SETTINGS_SOURCE" ]      || log_error_and_exit "settings.json 없음: $CLAUDE_SETTINGS_SOURCE"
[ -f "$CLAUDE_STATUSLINE_SOURCE" ]    || log_error_and_exit "statusline-command.sh 없음: $CLAUDE_STATUSLINE_SOURCE"
[ -d "$CLAUDE_SKILLS_SOURCE" ]        || log_error_and_exit "skills 디렉토리 없음: $CLAUDE_SKILLS_SOURCE"
[ -d "$CLAUDE_DOCS_SOURCE" ]          || log_error_and_exit "docs 디렉토리 없음: $CLAUDE_DOCS_SOURCE"
[ -d "$CLAUDE_GLOBAL_MEMORY_SOURCE" ] || log_error_and_exit "global-memory 없음: $CLAUDE_GLOBAL_MEMORY_SOURCE"

# Auto-migrate legacy statusLine.command in claude/settings.json before any
# downstream symlink uses it (issue #300, item A). Idempotent — only acts
# on the exact PR #292 legacy literal, otherwise no-op.
_migrate_legacy_statusline_command

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

# settings.local.json 은 dotfiles 가 직접 관리하지 않는다 (#584).
# Internal-PC 의 Bedrock 모델 매핑은 aws/setup.sh 가 Bedrock 템플릿으로
# jq-머지한다 (#677 F-7). 이전 게이트웨이 자동 생성 분기는 #683 F-2 에서 제거.

# Setup-mode SSOT read (issue #571). Reuses the _dotfiles_setup_mode
# helper sourced from shell-common/tools/integrations/claude.sh (line
# 478 above) — single source of canonicalisation for both the symbolic
# names emitted by shell-common/setup.sh and any legacy "1|2|3" files
# from pre-#571 installs.
_setup_mode=$(_dotfiles_setup_mode)

# 마이그레이션 미수행 가드는 mkdir 보다 먼저 — 그래야 stale ~/.claude 가
# 가드 디렉토리 생성으로 가려지지 않는다. SSOT: _claude_has_unmigrated_data
# (shell-common/tools/integrations/claude.sh)
#
# Internal mode bypasses this guard entirely — single-account layout uses
# ~/.claude/ directly, so "unmigrated data" is the expected state, not an
# error (issue #571, F-1).
if [ "$_setup_mode" != "internal" ] && _claude_has_unmigrated_data; then
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

# Single-account symlink helper for internal-PC mode (issue #571, F-1).
# Idempotent: correct target → no-op; wrong target → recreate; legacy
# bind-mount → unmount + symlink; existing regular file/dir → timestamped
# backup then symlink.
_single_account_ensure_link() {
    local src="$1" tgt="$2"
    if [ -L "$tgt" ]; then
        if [ "$(readlink "$tgt")" = "$src" ]; then
            log_dim "  ✓ already linked: $tgt → $src"
            return 0
        fi
        rm -f "$tgt"
        log_warning "  symlink target mismatch — recreating: $tgt"
    elif _is_mounted "$tgt"; then
        # Legacy multi-account-era bind mount surviving on a single-account
        # internal PC. `mv` would fail with EBUSY because the kernel refuses
        # to rename a mount point. Unmount first, then fall through to the
        # normal `ln -s` path below. The mount source typically already
        # points at the same dotfiles SSOT, so the swap is content-neutral.
        log_warning "  bind-mount detected at $tgt — unmounting (sudo may prompt)"
        if ! sudo umount "$tgt"; then
            log_error "  unmount 실패: $tgt"
            log_error "  수동 복구: sudo umount '$tgt' && rmdir '$tgt' && ./setup.sh"
            return 1
        fi
        log_dim "  ✓ unmounted: $tgt"
        # The bind mask is gone; the empty underlying directory is back.
        # Remove it so the symlink below can take its place.
        rmdir "$tgt" 2>/dev/null || true
    elif [ -e "$tgt" ]; then
        local backup
        backup="${tgt}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$tgt" "$backup" || {
            log_error "backup failed: $tgt → $backup"
            return 1
        }
        log_warning "  backed up: $tgt → $backup"
    fi
    mkdir -p "$(dirname "$tgt")"
    ln -s "$src" "$tgt" || {
        log_error "symlink failed: $tgt → $src"
        return 1
    }
    log_info "  symlink: $tgt → $src"
}

# Internal-PC single-account branch (issue #571, F-1; updated for #584, #683, #687).
# Direct-symlink the dotfiles SSOT into ~/.claude/ — no claude-accounts,
# no ~/.claude-personal, no ~/.claude-work.
#
# #687: settings.json 은 더 이상 symlink 가 아니다. aws/setup.sh 가
# dotfiles SSOT (claude/settings.json) + Bedrock 오버레이를 jq deep-merge
# 한 결과를 ~/.claude/settings.json 에 실파일로 작성한다. Claude Code 의
# settings.local.json deep-merge 가 사용자 환경에서 신뢰 불가하기 때문
# (실측 사례: ANTHROPIC_DEFAULT_SONNET_MODEL 미반영 → 400 invalid model).
# 그래서 본 분기에서는 settings.json 처리를 aws/setup.sh 에 위임한다.
# settings.local.json 은 #683 F-2 부터 본 분기가 만들지 않으며, #687 부터는
# aws/setup.sh 도 만들지 않고 기존 파일이 있으면 deprecation 안내만 한다.
if [ "$_setup_mode" = "internal" ]; then
    log_info "Internal PC mode — single-account setup (skipping claude-accounts)"

    # settings.json 처리는 aws/setup.sh 가 책임진다 (#687). 본 분기는 이
    # 파일에 손대지 않아 aws/setup.sh 가 작성한 실파일이 보존된다.
    _single_account_ensure_link "$CLAUDE_STATUSLINE_SOURCE"             "$HOME_STATUSLINE"
    _single_account_ensure_link "$CLAUDE_SKILLS_SOURCE"                 "$HOME_SKILLS"
    _single_account_ensure_link "$CLAUDE_DOCS_SOURCE"                   "$HOME_DOCS"
    _single_account_ensure_link "$CLAUDE_GLOBAL_MEMORY_SOURCE"          "$HOME_GLOBAL_MEMORY"
    _single_account_ensure_link "$HOME/.claude-shared/plugins"          "$HOME/.claude/plugins"

    # --- Verify Links (single-account) ---
    # settings.json is intentionally absent from this list — aws/setup.sh
    # writes it as a regular file (#687). settings.local.json is also
    # absent — deprecated (#687) and never a dotfiles symlink (#584).
    log_debug "\n--- 심볼릭 링크 확인 (internal/single-account) ---"
    for link in statusline-command.sh skills docs plugins projects/GLOBAL/memory; do
        if [ -L "$HOME/.claude/$link" ]; then
            log_dim "✓ ~/.claude/$link 심볼릭 링크 확인됨"
        else
            log_error_and_exit "$HOME/.claude/$link 심볼릭 링크 생성 실패"
        fi
    done

    _setup_gemini_skills_symlink

    log_debug "--- Claude Code dotfiles setup 완료 (internal/single-account) ---"
    echo ""
    ux_success "Claude Code 단일 계정 설정 완료 (internal PC mode)"
    ux_info "Config dir: $HOME/.claude"
    echo ""
    ux_section "다음 단계"
    ux_bullet "쉘 재시작: ${UX_BOLD}exec zsh${UX_RESET} 또는 ${UX_BOLD}exec bash${UX_RESET}"
    ux_bullet "실행: ${UX_BOLD}claude-yolo${UX_RESET} (멀티 계정 우회됨)"
    echo ""

    # settings.local.json 의 Bedrock 모델 매핑은 aws/setup.sh 가 책임진다 (#677 F-7).
    # 이전의 _print_internal_local_env_guidance 호출은 #683 F-2 에서 제거됨 —
    # 같은 ./setup.sh 안에서 게이트웨이 블록 (env: ANTHROPIC_BASE_URL /
    # ANTHROPIC_AUTH_TOKEN / ANTHROPIC_MODEL) 을 만들고 곧바로 aws/setup.sh
    # 가 strip 하던 자기상충 흐름을 정리. 위 3 env 키는 모두 deprecate.

    # Surface stale /etc/sudoers.d/claude-{skills,docs}-mount-* files left
    # behind from any prior multi-account install on this box.
    _print_stale_bind_mount_sudoers_hint

    exit 0
fi

# 활성 계정 목록을 한 번만 조회하여 재사용 (PR #292 review 반영)
ENABLED_ACCOUNTS=$(_claude_resolve_account --list)

# 활성화된 계정마다 symlink 셋업 (#575: bind-mount sudoers 제거됨).
# CLAUDE_SKIP_SUDOERS / CLAUDE_SKIP_BIND_MOUNT 환경 변수는 더 이상 어떤
# 동작도 게이트하지 않지만, 기존 테스트 하니스가 셋팅한 채로 들어와도
# 무해하다.
for acct in $ENABLED_ACCOUNTS; do
    cdir=$(_claude_resolve_account "$acct")
    log_info "Account: $acct → $cdir"
    _claude_account_setup_one "$acct" "$cdir"
done

# --- Verify Links (모든 활성 계정) ---
log_debug "\n--- 심볼릭 링크 확인 ---"
for acct in $ENABLED_ACCOUNTS; do
    cdir=$(_claude_resolve_account "$acct")
    for link in settings.json statusline-command.sh skills docs plugins projects/GLOBAL/memory; do
        if [ -L "${cdir}/${link}" ]; then
            log_dim "✓ ${acct}/${link} 심볼릭 링크 확인됨"
        else
            log_error_and_exit "${acct}/${link} 심볼릭 링크 생성 실패"
        fi
    done
done

# Gemini CLI 설치 시 ~/.gemini/skills → claude/skills SSOT symlink 설정 (issue #562).
_setup_gemini_skills_symlink

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

# Surface stale /etc/sudoers.d/claude-{skills,docs}-mount-* files left
# behind from the pre-#575 bind-mount layout. Cleanup is manual on
# purpose so setup.sh never has to prompt for sudo.
_print_stale_bind_mount_sudoers_hint

echo ""

exit 0
