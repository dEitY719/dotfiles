#!/bin/bash

# claude/setup.sh: Claude Code environment setup
#
# PURPOSE: Set up Claude Code configuration with symbolic links
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL INITIALIZATION (why this file is REQUIRED):
#   Provisions every Claude config dir (multi-account ~/.claude-<acct>, or
#   ~/.claude on an internal PC) from _claude_link_table — the single list of
#   settings.json copy / symlinks / skills dir (claude_accounts_lifecycle.sh,
#   #2141) — then verifies the result. main() runs the _phase_* functions.
#
# Internal mode 에서 ~/.claude/settings.json 은 (2026-08-18 부터) 조직 LLM
# Gateway 전환 도구 `gateway-cli setup` 이 소유·작성한다 — dotfiles 는 이
# 파일을 만들거나 덮어쓰지 않는다. 구 SSOT+오버레이 jq deep-merge(#687)는
# 폐지됐다. 본 스크립트는 internal 분기에서
# settings.json symlink 를 만들지 않으며, dotfiles SSOT 의 `.hooks`/
# `.statusLine` 만 SessionStart 훅(claude/hooks/session-start-settings-drift.sh)
# 이 사내 모드에서 live 파일에 자동 복구한다. ~/.claude/settings.local.json 은
# #924 이후 개인 override 의 정식 슬롯이라 본 스크립트는 건드리지 않는다.
#
# These files/directories are version-controlled in dotfiles and should
# be managed via symbolic links for consistency across machines.
#
# See docs/guide/setup.md for more information

# log_info / log_warning / log_error / log_error_and_exit come from
# shell-common/lib/setup/common.sh (sourced via link.sh in _phase_load_libs,
# #2137). Only the dim check-mark line has no shared equivalent.
log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }

# --- Phase 1: libraries + path constants ---

# _phase_load_libs — resolve DOTFILES_ROOT, set the path constants and source
# every library the later phases call. Definitions only, no provisioning.
_phase_load_libs() {
    # Initialize DOTFILES_ROOT
    _SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
    DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

    # Canonicalize to the main worktree (issue #589). When invoked from a
    # linked worktree, the script path resolves to <worktree>/claude/setup.sh
    # and DOTFILES_ROOT becomes the worktree — that path would then be baked
    # into every ~/.claude-*/ symlink we create below. Falling through to the
    # worktree path is acceptable if the helper is missing (no regression).
    _CLAUDE_DOTFILES_RESOLVER="${DOTFILES_ROOT}/shell-common/lib/dotfiles_root.sh"
    if [ -r "$_CLAUDE_DOTFILES_RESOLVER" ]; then
        # shellcheck source=../shell-common/lib/dotfiles_root.sh
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

    # Dotfiles source locations
    CLAUDE_SETTINGS_SOURCE="${CLAUDE_DOTFILES}/settings.json"

    # Load UX library (unified library at shell-common/tools/ux_lib/)
    UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
    if [ -f "$UX_LIB" ]; then
        source "$UX_LIB"
    else
        echo "Error: UX library not found at $UX_LIB"
        exit 1
    fi

    # Idempotent link lib (#2137, #2138): dotfiles_ensure_link replaces the former
    # _single_account_ensure_link. Its common.sh also supplies the log_*
    # helpers every later phase uses.
    # shellcheck source=../shell-common/lib/setup/link.sh
    . "${DOTFILES_ROOT}/shell-common/lib/setup/link.sh" || exit 1

    # Load mount utilities (provides _is_mounted).
    #
    # shell-common/functions/mount.sh defines its pure helpers (_is_mounted)
    # above its interactive guard, so a plain non-interactive source is enough.
    MOUNT_LIB="${DOTFILES_ROOT}/shell-common/functions/mount.sh"
    if [ -f "$MOUNT_LIB" ]; then
        . "$MOUNT_LIB"
    else
        log_error_and_exit "Mount library not found at $MOUNT_LIB"
    fi

    if ! declare -f _is_mounted >/dev/null 2>&1; then
        log_error_and_exit "Mount library did not define _is_mounted: $MOUNT_LIB"
    fi

    # Load workspace skill-source helpers (issue #1652), used by
    # _claude_prune_workspace_skills to recognize (and remove) flat workspace
    # skill links in the Claude Code skills dirs — Claude Code loads those skills
    # via plugins (claude/plugin/plugins.json), not via flat links. A pure
    # function library with no interactive guard. The declare-f assertion is
    # the #724 lesson: without it a missing definition makes the cleanup silently
    # no-op rather than fail.
    SKILL_SOURCES_LIB="${DOTFILES_ROOT}/shell-common/lib/skill_sources.sh"
    if [ -f "$SKILL_SOURCES_LIB" ]; then
        . "$SKILL_SOURCES_LIB"
    else
        log_error_and_exit "Skill sources library not found at $SKILL_SOURCES_LIB"
    fi

    if ! declare -f _skill_workspace_root >/dev/null 2>&1; then
        log_error_and_exit "Skill sources library did not define _skill_workspace_root: $SKILL_SOURCES_LIB"
    fi

    # 다중 계정 함수 source (env + account libs, #2146).
    # env/claude.sh 와 tools/custom/lib/claude_accounts_*.sh 는 interactive guard
    # 없는 순수 정의 파일이라 비대화형 setup 에서도 그대로 source 된다. 예전엔
    # tools/integrations/claude.sh 를 guard 우회 신호와 함께 source 했다(#554).
    . "$DOTFILES_ROOT/shell-common/env/claude.sh"
    for _claude_accounts_lib in auth lifecycle skills; do
        # shellcheck source=/dev/null
        . "$DOTFILES_ROOT/shell-common/tools/custom/lib/claude_accounts_${_claude_accounts_lib}.sh" || exit 1
    done
    unset _claude_accounts_lib
}

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
    # Latest-only backup (issue #919): a fixed suffix overwrites the prior
    # backup instead of stamping a new timestamped file each run, and the
    # glob sweeps any legacy timestamped backups left by pre-#919 runs.
    # SSOT policy: shell-common/lib/dotfiles_backup.sh (#806).
    local backup
    backup="${backup_dir}/settings.json.pre-statusline-fix.backup"
    rm -f "${backup_dir}/settings.json.pre-statusline-fix-"*
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
        SETUP_MIGRATIONS=$((SETUP_MIGRATIONS + 1))  # 변경 요약 집계 (#997)
    else
        rm -f "$tmp"
        log_error "settings.json 갱신 실패 — 백업 보존: $backup"
        return 1
    fi
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
    # Normalize to the *shared* physical plugin dir, NOT the active account's
    # dir. Every per-account ~/.claude-<acct>/plugins is a symlink INTO
    # ~/.claude-shared/plugins (wired by _claude_ensure_symlink in
    # _claude_account_setup_one), and installed_plugins.json itself lives in
    # the shared dir and is read by *all* accounts. The previous code aimed
    # at the active account's dir (~/.claude-<active>/plugins/), which made
    # the recorded prefix volatile: switching the active account and re-running
    # setup
    # rewrote every path to the new account (2건씩 재마이그레이션 + backup
    # 덮어쓰기) even though nothing physically moved — all prefixes resolve
    # through the symlink to the same shared files anyway. The shared dir is
    # a stable fixed point, so the migration converges and later runs are
    # 0건 regardless of which account is active when setup runs.
    local new_prefix="${plugins_root}/"
    # Match any ${HOME}/.claude(-suffix)?/plugins/ — the legacy ${HOME}/.claude/
    # form from #340 plus every per-account variant (.claude-shared itself
    # matches too, so already-normalized entries skip via the startswith($new)
    # guard in the jq filters). $HOME is interpolated literally (not as a
    # regex), so an unusual $HOME containing regex meta-chars would
    # over-match; acceptable for our environment.
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
        # Latest-only backup (issue #919): fixed suffix + legacy sweep so
        # repeat multi-account runs do not accumulate one backup per run.
        # SSOT policy: shell-common/lib/dotfiles_backup.sh (#806).
        backup="${file}.pre-plugin-path-fix.backup"
        rm -f "${file}".pre-plugin-path-fix-*
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
            # Successful idempotent migration — info severity so ⚠️ stays
            # reserved for items needing user action (issue #995).
            log_info "$(basename "$file") plugin 경로 마이그레이션: ${stale_count}건 → ${new_prefix}"
            log_info "  backup: $backup"
            SETUP_MIGRATIONS=$((SETUP_MIGRATIONS + 1))  # 변경 요약 집계 (#997)
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
        log_warning "  참조: gh-flow:issue 스킬의 references/stop-guard.md (gh-flow-skills 플러그인)"
        return 0
    fi

    local backup tmp
    # Latest-only backup (issue #919): fixed suffix + legacy sweep.
    # SSOT policy: shell-common/lib/dotfiles_backup.sh (#806).
    backup="${source_file}.pre-stop-hook-fix.backup"
    rm -f "${source_file}".pre-stop-hook-fix-*
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
        SETUP_MIGRATIONS=$((SETUP_MIGRATIONS + 1))  # 변경 요약 집계 (#997)
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

# NOTE (issue #791): the previous `_setup_gemini_skills_symlink` helper
# was retired. It created ~/.gemini/skills as a directory symlink to the
# SSOT — but #791 converged Gemini / OpenCode / Codex onto the same
# entry-level synthesis layout Claude Code uses (#707, F-8), so
# `scripts/setup-skills-ssot.sh` (which runs after claude/setup.sh in
# ./setup.sh) is now the single owner of ~/.gemini/skills and performs
# both the migration (legacy dir-symlink → real dir) and the entry-level
# synthesis. Leaving the old helper in place would re-create the legacy
# dir-symlink one step before setup-skills-ssot.sh tears it back down —
# correct in the end but noisy and confusing.

# _print_stale_bind_mount_sudoers_hint — surface (and optionally clean
# up) stale /etc/sudoers.d/ files left over from the pre-#575 bind-mount
# design.
#
# Issue #575 removed _setup_bind_mount_sudoers and the entire bind-mount
# integration in favour of directory-level symlinks. Existing PCs may
# still carry sudoers entries from the prior layout — they no longer
# match anything in the setup and only widen the sudoers surface, so
# point the user at them.
#
# Issue #762: when stdin/stdout are a TTY and the caller did not opt out
# via DOTFILES_NONINTERACTIVE=1, ask once whether to delete the files
# via `sudo rm`. On any other condition (non-interactive run, declined
# prompt, sudo failure) fall back to the original manual-command hint
# so the user still has a copy-paste path.
_print_stale_bind_mount_sudoers_hint() {
    local sudoers_glob='/etc/sudoers.d/claude-skills-mount-* /etc/sudoers.d/claude-docs-mount-*'
    local found=""
    local count=0
    # shellcheck disable=SC2086  # glob intentionally unquoted
    for _f in $sudoers_glob; do
        [ -f "$_f" ] || continue
        found="${found}  $_f
"
        count=$((count + 1))
    done

    [ -n "$found" ] || return 0

    ux_info ""
    ux_section "Stale bind-mount sudoers (issue #575)"
    ux_info "Issue #575 retired bind-mount for Claude skills/docs in favour of"
    ux_info "a single directory symlink. The sudoers files below were created"
    ux_info "by an earlier dotfiles version and no longer have a matching"
    ux_info "consumer — they only widen the sudoers surface."
    ux_info ""
    printf '%s' "$found"
    ux_info ""

    if [ -t 0 ] && [ -t 1 ] && [ "${DOTFILES_NONINTERACTIVE:-0}" != "1" ]; then
        if ux_confirm "Stale sudoers files detected (${count}). 자동 정리하시겠습니까?" "n"; then
            # shellcheck disable=SC2086  # glob intentionally unquoted
            if sudo rm -f $sudoers_glob; then
                ux_success "Stale sudoers files 정리 완료."
                return 0
            fi
            ux_warning "Stale sudoers files 정리 실패 — 아래 명령을 수동으로 실행하세요:"
        fi
    fi

    ux_bullet "Quick command:"
    cat <<'EOF'

    sudo rm -f /etc/sudoers.d/claude-skills-mount-* \
               /etc/sudoers.d/claude-docs-mount-*

EOF
}

# Note: 이전에 있던 `_print_internal_local_env_guidance` 는 #683 F-2 에서 제거.
# 사내 PC 의 live ~/.claude/settings.json 은 (2026-08-18 부터) `gateway-cli
# setup` 이 쓴다 — 구 SSOT+오버레이 jq deep-merge (#687)는 폐지됐다.
# `env.ANTHROPIC_BASE_URL` 등은 예전엔 레거시 게이트웨이 키(#677 O-1)로
# 취급돼 strip 대상이었지만, 지금은 gateway-cli 가 쓰는 정상 키다 — strip 로직 자체가 없어졌다.

# --- Phases (issue #2141): main() below runs them in order ---

# _print_change_summary — 완료 메시지 직전 "이번 실행에서 바뀐 것" 한 줄
# 롤업 (#997). 사용자가 로그 전체를 훑지 않고도 변경 규모를 파악하게 한다.
# 최소 집계 원칙(#997 비범위): 마이그레이션 건수 + 정리한 워크스페이스 스킬
# 링크 수. Claude Code 스킬은 플러그인(claude/plugin/plugins.json)이 단일
# SSOT 라 더 이상 합성하지 않는다 — 대신 _claude_prune_workspace_skills 가
# 예전 합성이 남긴 flat 링크를 지우며 CLAUDE_WS_SKILLS_PRUNED 에 누적한다
# (계정 루프의 최상위 셸에서 호출되므로 서브셸 없이 값이 전파된다).
# 인자 $1 이 있으면 뒤에 추가(예: 다중 계정 분기의 활성 계정 수).
_print_change_summary() {
    ux_info "요약: 마이그레이션 ${SETUP_MIGRATIONS}건 · 워크스페이스 스킬 링크 정리 ${CLAUDE_WS_SKILLS_PRUNED:-0}개 (스킬은 플러그인으로 로드)${1:+ · $1}"
}

# _phase_preflight — 필수 SSOT 소스 검증, setup 모드 판정, 미마이그레이션
# 가드, 가드 디렉토리 생성, /sandbox 의존성 점검.
_phase_preflight() {
    # 필수 dotfiles source 검증
    # settings.json 은 이제 tracked SSOT (#584) — 부트스트랩/템플릿 단계 불필요.
    [ -f "$CLAUDE_SETTINGS_SOURCE" ]      || log_error_and_exit "settings.json 없음: $CLAUDE_SETTINGS_SOURCE"
    # 나머지 소스는 _claude_link_table 의 src 칸에서 파생 — 행을 추가하면 검증도
    # 따라온다 (#2141). dir 행(-)과 @shared 는 dotfiles 소스가 아니라 건너뛴다.
    local _pf_src _pf_rel _pf_path
    while IFS='|' read -r _pf_src _pf_rel _ <&3; do
        case "$_pf_src" in - | @*) continue ;; esac
        _pf_path=$(_claude_link_src "$_pf_src")
        [ -e "$_pf_path" ] || log_error_and_exit "${_pf_rel} 없음: $_pf_path"
    done 3<<EOF
$(_claude_link_table)
EOF

    # Setup-mode SSOT read (issue #571). Reuses the _dotfiles_setup_mode
    # helper sourced via tools/custom/lib/claude_accounts_auth.sh (above)
    # — single source of canonicalisation for both the symbolic
    # names emitted by shell-common/setup.sh and any legacy "1|2|3" files
    # from pre-#571 installs.
    _setup_mode=$(_dotfiles_setup_mode)

    # 마이그레이션 미수행 가드는 mkdir 보다 먼저 — 그래야 stale ~/.claude 가
    # 가드 디렉토리 생성으로 가려지지 않는다. SSOT: _claude_has_unmigrated_data
    # (shell-common/tools/custom/lib/claude_accounts_lifecycle.sh)
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

    # /sandbox 의존성 점검 (issue #340).
    _check_socat_for_sandbox
}

# _phase_migrate — 멱등 마이그레이션 3종 (statusLine / Stop hook / plugin 경로).
# 서브셸 없이 호출돼 SETUP_MIGRATIONS 증가가 main 의 셸에 그대로 남는다 (#997).
_phase_migrate() {
    # Auto-migrate legacy statusLine.command in claude/settings.json before any
    # downstream symlink uses it (issue #300, item A). Idempotent — only acts
    # on the exact PR #292 legacy literal, otherwise no-op.
    _migrate_legacy_statusline_command

    # Auto-install gh-issue-flow Stop hook (issue #383). Idempotent — only adds
    # the entry when it's missing AND no conflicting Stop hook is configured.
    _migrate_install_gh_issue_flow_stop_hook

    # Claude Code plugin 경로 마이그레이션 (issue #340). 멱등 — 옛 prefix 가
    # 남아있을 때만 갱신, 그 외 no-op. 백업은 timestamped 보존.
    _migrate_legacy_plugin_paths
}

# Internal-PC single-account branch (issue #571, F-1; updated for #584, #683, #687).
# Direct-symlink the dotfiles SSOT into ~/.claude/ — no claude-accounts,
# no ~/.claude-personal, no ~/.claude-work.
#
# settings.json 은 symlink 가 아니라 실파일이지만, (2026-08-18 부터) 그 실파일의
# writer 는 dotfiles 가 아니라 `gateway-cli setup` (조직 LLM Gateway 전환 도구)
# 이다. 구 #687 설계(SSOT + 오버레이를 jq deep-merge)
# 는 폐지됐다 — gateway-cli 가 apiKeyHelper/env.* 를 직접 쓰는 같은 파일을
# dotfiles 가 다시 덮어쓰면 두 writer 가 서로를 지우는 왕복이 되기 때문
# (실측 사례: gateway-cli 가 .statusLine 을 자기 바이너리로 덮어씀). 그래서
# 본 분기(이 스크립트)는 settings.json 을 아예 건드리지 않는다. dotfiles
# SSOT 의 `.hooks`/`.statusLine` 만 SessionStart 훅(session-start-settings-
# drift.sh)이 사내 모드에서 live 파일에 자동 복구한다. settings.local.json
# 은 #924 이후 개인 override 의 정식 슬롯이라 본 분기도 건드리지 않는다.
# 단 예외 하나 — 그 드리프트 훅 자신의 `.hooks.SessionStart` 등록이 사라지면
# `claude/tools/register-drift-hook.sh` 가 그 1건만 되살린다 (F-7b, #1364).
_phase_provision_internal() {
    log_info "Internal PC mode — single-account setup (skipping claude-accounts)"

    # settings.json 은 gateway-cli setup 이 소유한다 — 본 분기는 이 파일에
    # 손대지 않는다. dotfiles SSOT 변경은 session-start-settings-drift.sh 가 전파.
    _claude_install_herdr_hook "$HOME/.claude"
    # F-7b (#1364): restore only the drift-heal hook's own registration.
    bash "$DOTFILES_ROOT/claude/tools/register-drift-hook.sh" || true
    # 링크 목록은 _claude_link_table 1곳 (#2141) — modes 필터로 settings.json
    # (multi 전용) 이 빠진다. 이 분기는 _claude_account_setup_one 을 타지 않으므로
    # (#571, internal PC 는 단일 계정) 같은 테이블을 여기서 직접 적용한다.
    _claude_link_apply internal "$HOME/.claude"
}

# _phase_provision_multi — 활성 계정마다 _claude_account_setup_one.
_phase_provision_multi() {
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
}

# 접두사 없는 $HOME/.claude 는 어떤 계정에도 속하지 않아 위 루프의 대상이
# 아니지만, claude-yolo / claude-yolo-<account> 래퍼를 거치지 않고 맨몸
# `claude` 를 실행하면 Claude Code 가 기본값으로 쓰는 경로이기도 하다
# (issue #1701). 계정 루프와 별도로, 여기도 같은 실파일화를 적용해
# write-through 심볼릭 링크가 SSOT 를 오염시키는 경로를 막는다.
#
# 계정 디렉터리와 달리 이 경로는 지금까지 setup.sh 가 전혀 관리하지 않았다
# — 심볼릭 링크(#1701 재현 상태)나 부재 상태만 예상되지만, 사용자가 손으로
# 만든 실파일이 이미 있을 가능성을 배제할 수 없다. _claude_ensure_settings_copy
# 는 그런 실파일을 model/enabledPlugins 를 제외하고 SSOT 로 조용히 덮어쓰므로
# (#940 기존 동작), 최초 이 경로를 넘겨받는 지금만 한 번 백업해 데이터 손실을
# 막는다 (PR #1702 codex review BLOCKER). 심볼릭 링크·부재 상태는 잃을 실체가
# 없으므로 백업 대상이 아니다 — _migrate_legacy_statusline_command 의
# ${HOME}/.claude-backups/ latest-only 백업 관례(#919)를 그대로 따른다.
#
# 백업 파일이 이미 있으면 최초 인수 보호는 끝난 것으로 본다. 설치 후에도
# _claude_ensure_settings_copy 가 model/enabledPlugins 를 보존하므로 이 파일은
# 항상 SSOT 와 cmp 상 달라진다 — 백업 존재 여부로 게이트하지 않으면 매 실행
# 경고+백업(덮어쓰기)이 반복돼 비멱등이 된다.
_phase_provision_bare() {
    _bare_claude_backup_dir="${HOME}/.claude-backups"
    _bare_claude_backup="${_bare_claude_backup_dir}/settings.json.pre-1701-bare-claude.backup"
    if [ -f "$HOME/.claude/settings.json" ] && [ ! -L "$HOME/.claude/settings.json" ] \
        && [ ! -e "$_bare_claude_backup" ] \
        && ! cmp -s "$CLAUDE_SETTINGS_SOURCE" "$HOME/.claude/settings.json"; then
        if mkdir -p "$_bare_claude_backup_dir"; then
            if cp "$HOME/.claude/settings.json" "$_bare_claude_backup"; then
                log_warning "\$HOME/.claude/settings.json 이 SSOT 와 다른 기존 실파일 — 백업 후 SSOT 로 교체:"
                log_warning "  backup: $_bare_claude_backup"
            else
                log_error "\$HOME/.claude/settings.json 백업 실패 — 실파일 전환 중단"
                _bare_claude_backup_failed=1
            fi
        else
            log_error "백업 디렉토리 생성 실패: $_bare_claude_backup_dir — 실파일 전환 중단"
            _bare_claude_backup_failed=1
        fi
    fi
    if [ "${_bare_claude_backup_failed:-0}" != "1" ]; then
        log_info "Bare config dir: \$HOME/.claude"
        _claude_ensure_settings_copy "$CLAUDE_SETTINGS_SOURCE" "$HOME/.claude/settings.json"
    fi
}

# _claude_link_verify <mode> <cdir> <label> — _claude_link_table 의 <mode> 행이
# <cdir> 에 기대한 형태로 있는지 확인한다 (#2141). 실패는 log_error_and_exit.
# skills/ 는 실디렉토리 (#707, F-8) — 스킬은 플러그인에서 오므로 비어 있어도 된다.
# settings.json 은 #940 이후 실파일 복사 — symlink 는 /model 이 SSOT 를 오염시킨다 (#924).
_claude_link_verify() {
    local mode="$1" cdir="$2" label="$3" rel kind modes
    while IFS='|' read -r _ rel kind modes <&3; do
        case "$modes" in all | "$mode") ;; *) continue ;; esac
        case "$kind" in
        copy)
            if [ -f "${cdir}/${rel}" ] && [ ! -L "${cdir}/${rel}" ]; then
                log_dim "✓ ${label}/${rel} 실파일 확인됨"
            else
                log_error_and_exit "${label}/${rel} 실파일 생성 실패"
            fi
            ;;
        link)
            if [ -L "${cdir}/${rel}" ]; then
                log_dim "✓ ${label}/${rel} 심볼릭 링크 확인됨"
            else
                log_error_and_exit "${label}/${rel} 심볼릭 링크 생성 실패"
            fi
            ;;
        dir)
            if [ -d "${cdir}/${rel}" ] && [ ! -L "${cdir}/${rel}" ]; then
                log_dim "✓ ${label}/${rel} 실디렉토리 확인됨 (스킬은 플러그인으로 로드)"
            else
                log_error_and_exit "${label}/${rel} 실디렉토리 생성 실패 (디렉토리 아님)"
            fi
            ;;
        esac
    done 3<<EOF
$(_claude_link_table)
EOF
}

# _phase_verify — 산출물 검증. 실패는 log_error_and_exit (exit 1).
_phase_verify() {
    if [ "$_setup_mode" = "internal" ]; then
        # --- Verify Links (single-account) ---
        # settings.json (multi 전용 행) 은 검증 대상이 아니다 — gateway-cli
        # setup 이 실파일로 쓴다 (2026-08-18~, #687 머지 폐지). settings.local.json
        # 은 개인 override 슬롯(#924)이라 테이블에 없다 (#584).
        ux_section "심볼릭 링크 확인 (internal/single-account)"
        # shellcheck disable=SC2088  # 표시용 라벨 — 확장하지 않는다
        _claude_link_verify internal "$HOME/.claude" "~/.claude"
        return 0
    fi

    # --- Verify Links (모든 활성 계정 + 접두사 없는 \$HOME/.claude) ---
    ux_section "심볼릭 링크 확인"
    for acct in $ENABLED_ACCOUNTS; do
        _claude_link_verify multi "$(_claude_resolve_account "$acct")" "$acct"
    done
    # 접두사 없는 \$HOME/.claude/settings.json 도 실파일이어야 한다 (#1701) —
    # 위 계정 루프와 달리 심볼릭 링크·docs·skills 등 다른 항목은 이 경로에서
    # 관리하지 않으므로 settings.json 하나만 검증한다.
    if [ -f "$HOME/.claude/settings.json" ] && [ ! -L "$HOME/.claude/settings.json" ]; then
        log_dim "✓ \$HOME/.claude/settings.json 실파일 확인됨"
    else
        log_error_and_exit "\$HOME/.claude/settings.json 실파일 생성 실패"
    fi

    # cache-watch mod (#2026) 로드 연결 — SSOT settings.json 의 env.CLAUDE_CODE_PLUGIN_DIRS
    # 가 위 _claude_ensure_settings_copy 로 각 계정에 복사돼 매 세션 mod 를 로드한다
    # (--plugin-dir 수동 지정 불필요). 경로는 statusLine 과 같은 ~/dotfiles 기준.
    # soft-fail: 복사 누락이나 mod 디렉토리 부재는 경고만 한다.
    _cw_mod_dir="${HOME}/dotfiles/claude/mods/cache-watch"
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq 미설치 — cache-watch mod 로드 설정 확인 건너뜀"
    elif [ -d "$_cw_mod_dir/.claude-plugin" ]; then
        for acct in $ENABLED_ACCOUNTS; do
            _cw_live="$(_claude_resolve_account "$acct")/settings.json"
            if jq -e '.env.CLAUDE_CODE_PLUGIN_DIRS // empty' "$_cw_live" >/dev/null 2>&1; then
                log_dim "✓ ${acct} cache-watch mod 로드 설정 확인됨 (env.CLAUDE_CODE_PLUGIN_DIRS)"
            else
                log_warning "${acct}/settings.json 에 env.CLAUDE_CODE_PLUGIN_DIRS 없음 — cache-watch mod 미로드"
            fi
        done
    else
        log_warning "cache-watch mod 디렉토리 없음: $_cw_mod_dir — ~/dotfiles 가 이 체크아웃이 아니면 mod 가 로드되지 않는다"
    fi
    unset _cw_mod_dir _cw_live

    # OpenCode / Codex / Gemini / agy / Hermes entry-level 합성은
    # scripts/setup-skills-ssot.sh 가 책임짐 (#791, #1376, #1731) — 플러그인 기반이
    # 아닌 이 harness 들만 flat 합성을 쓴다 (Claude Code 는 플러그인 전용). agy 는 Gemini 런타임을
    # 공유하지만 skill 검색 경로는 상속하지 않아 ~/.gemini/config/skills 에 따로 합성한다
    # (agy/AGENTS.md 참고).
    # 이전엔 본 분기에서 _setup_gemini_skills_symlink 를 호출했지만, #791 에서
    # entry-level 합성으로 통일했고 SSOT 는 setup-skills-ssot.sh 로 이전됐다.
    # #1376 에서 Hermes 가, #1731 에서 agy 가 대상으로 추가됐다 (Hermes 만 전용
    # 서브디렉토리 ~/.hermes/skills/dotfiles/ 사용 — 루트는 Hermes hub/curator 소유).
}

# _phase_report — 변경 요약 + 완료/다음 단계 안내 + stale sudoers 힌트.
_phase_report() {
    if [ "$_setup_mode" = "internal" ]; then
        # OpenCode / Codex / Gemini / agy / Hermes entry-level 합성은
        # scripts/setup-skills-ssot.sh 가 책임짐 (#791, #1376, #1731) — 상세는
        # _phase_verify 끝 주석 참고.

        _print_change_summary  # 변경 요약 한 줄 (#997)
        ux_success "Claude Code dotfiles setup 완료 (internal/single-account)"
        ux_info ""
        ux_success "Claude Code 단일 계정 설정 완료 (internal PC mode)"
        ux_info "Config dir: $HOME/.claude"
        ux_info ""
        ux_section "다음 단계"
        ux_bullet "쉘 재시작: ${UX_BOLD}exec zsh${UX_RESET} 또는 ${UX_BOLD}exec bash${UX_RESET}"
        ux_bullet "실행: ${UX_BOLD}claude-yolo${UX_RESET} (멀티 계정 우회됨)"
        ux_info ""

        # settings.json 의 auth/env/모델 설정은 (2026-08-18 부터) gateway-cli setup
        # 이 책임진다 — dotfiles 는 관여하지 않는다 (구 #677 F-7 jq-머지
        # 폐지). 이전의 _print_internal_local_env_guidance 호출은 #683 F-2 에서
        # 이미 제거됨.

        # Surface stale /etc/sudoers.d/claude-{skills,docs}-mount-* files left
        # behind from any prior multi-account install on this box.
        _print_stale_bind_mount_sudoers_hint
        return 0
    fi

    # --- Completion Messages ---
    # 활성 계정 수는 네이티브 배열로 집계 — 외부 wc/tr 포크 회피 (PR #998 리뷰).
    # shellcheck disable=SC2206  # 공백/개행 구분 목록의 의도된 word-splitting.
    _caccts=($ENABLED_ACCOUNTS)
    _print_change_summary "활성 계정 ${#_caccts[@]}개"  # 변경 요약 한 줄 (#997)
    ux_success "Claude Code dotfiles setup 완료"
    ux_info ""
    ux_success "Claude Code 다중 계정 설정 완료!"
    ux_info "활성 계정: $(echo "$ENABLED_ACCOUNTS" | tr '\n' ' ')"
    ux_info "Default: $CLAUDE_DEFAULT_ACCOUNT"
    ux_info ""
    ux_section "다음 단계"
    ux_bullet "쉘 재시작 후 진단: ${UX_BOLD}claude-accounts status${UX_RESET}"
    ux_bullet "처음 사용: ${UX_BOLD}claude-yolo${UX_RESET} (브라우저로 ${CLAUDE_DEFAULT_ACCOUNT} 로그인)"
    ux_bullet "다른 계정: ${UX_BOLD}claude-yolo --user <name>${UX_RESET} 또는 ${UX_BOLD}claude-yolo-<name>${UX_RESET}"

    # Surface stale /etc/sudoers.d/claude-{skills,docs}-mount-* files left
    # behind from the pre-#575 bind-mount layout. Cleanup is manual on
    # purpose so setup.sh never has to prompt for sudo.
    _print_stale_bind_mount_sudoers_hint

    ux_info ""
}

main() {
    _phase_load_libs

    ux_section "Claude Code dotfiles setup"

    # 이번 실행에서 실제로 수행된 마이그레이션 건수 누적 (#997). 완료 직전
    # _print_change_summary 가 이 값을 변경 요약 라인에 집계한다. 마이그레이션
    # 함수들(statusLine / Stop hook / plugin 경로)은 모두 본 스크립트의 최상위
    # 셸에서 호출돼 서브셸 없이 값이 전파된다. model 이주(#940)는 sourced
    # claude.sh 의 _claude_ensure_settings_copy 에서 수행되지만 그 함수 역시
    # 계정 루프의 최상위 셸에서 직접 호출되므로 동일하게 이 값에 집계된다 (#1101).
    SETUP_MIGRATIONS=0

    _phase_preflight
    _phase_migrate

    # internal 은 _claude_account_setup_one 을 타지 않는다 (#571) — 단 예전
    # exit 0 조기 종료 대신 verify/report 를 다중 계정 경로와 공유한다 (#2141).
    if [ "$_setup_mode" = "internal" ]; then
        _phase_provision_internal
    else
        _phase_provision_multi
        _phase_provision_bare
    fi

    _phase_verify
    _phase_report
    return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
