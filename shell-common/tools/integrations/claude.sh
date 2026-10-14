#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/tools/claude.sh
# Claude Code CLI - setup, utilities, and workflow helpers
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Claude Code Installation
# Reference: https://code.claude.com/docs/en/getting-started
# ═══════════════════════════════════════════════════════════════
#
# Use: clinstall (runs official native installer)
# Use: delete_claude (uninstall and clean)
#
# Storage layout: skills/, docs/ are exposed to Claude Code via a single
# top-level directory symlink per account (issue #575). The legacy bind-
# mount path (#287) and the interim per-skill symlink path (#342, #344)
# were removed in favour of one symlink that mirrors the SSOT atomically
# and survives reboot without sudoers entries.

# ═══════════════════════════════════════════════════════════════
# Dependency Check: Ensure jq is installed
# ═══════════════════════════════════════════════════════════════

ensure_jq() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/ensure_jq.sh"
}

# NOTE: Do not auto-install dependencies at shell init time.
# If jq is required for a specific workflow, call `ensure_jq` explicitly.

# ═══════════════════════════════════════════════════════════════
# Claude Code Installation
# ═══════════════════════════════════════════════════════════════

clinstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_claude.sh"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Uninstallation
# ═══════════════════════════════════════════════════════════════

delete_claude() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/delete_claude.sh"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Configuration Initialization
# ═══════════════════════════════════════════════════════════════

claude_init() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local settings_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"
    local settings_target="$HOME/.claude/settings.json"
    local statusline_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/statusline-command.sh"
    local statusline_target="$HOME/.claude/statusline-command.sh"
    local skills_target_dir="$HOME/.claude/skills"

    ux_info "Initializing Claude Code configuration..."
    ux_info ""

    # Create ~/.claude directory if not exists
    if [ ! -d "$HOME/.claude" ]; then
        ux_info "Creating ~/.claude directory..."
        mkdir -p "$HOME/.claude"
    fi

    # Create ~/.claude/skills directory if not exists
    if [ ! -d "$skills_target_dir" ]; then
        ux_info "Creating ~/.claude/skills directory..."
        mkdir -p "$skills_target_dir"
    fi

    # Handle settings.json
    ux_section "Settings Configuration"
    if [ -L "$settings_target" ]; then
        ux_success "settings.json symbolic link already exists"
    elif _claude_link_lib && dotfiles_ensure_link "$settings_source" "$settings_target"; then
        # A regular file is moved to settings.json.original first (#806, #2138).
        ux_success "Created symbolic link for settings.json"
    fi
    ux_info ""

    # Handle statusline-command.sh
    ux_section "Statusline Configuration"
    if [ -L "$statusline_target" ]; then
        ux_success "statusline-command.sh symbolic link already exists"
    elif _claude_link_lib && dotfiles_ensure_link "$statusline_source" "$statusline_target"; then
        # A regular file is moved to statusline-command.sh.original first (#806, #2138).
        ux_success "Created symbolic link for statusline-command.sh"
    fi
    ux_info ""

    # Skills: Claude Code 는 워크스페이스 스킬을 플러그인으로만 로드한다
    # (claude/plugin/plugins.json). 예전 flat 합성(#1652 / #1680)이 남긴
    # 워크스페이스 링크만 정리하고 skills/ 는 실디렉토리로 유지한다.
    ux_section "Claude Code Skills"
    _claude_prune_workspace_skills "$skills_target_dir"
    ux_info ""

    ux_header "Claude Code Initialization Complete"
    ux_info ""

    ux_section "Configuration Files"
    for config_target in "$settings_target" "$statusline_target"; do
        if [ -e "$config_target" ]; then
            ls -la -- "$config_target"
        fi
    done
    ux_info ""

    # skills/ 는 실디렉토리 (#707 F-8) — 워크스페이스 스킬은 플러그인으로
    # 로드되므로 여기 남는 건 외부에서 추가된 entry 뿐이다.
    ux_section "Skills"
    if [ -d "$skills_target_dir" ]; then
        linked_skill_found=0
        for skill_target_file in "$skills_target_dir"/*; do
            if [ -e "$skill_target_file" ] || [ -L "$skill_target_file" ]; then
                ls -lad -- "$skill_target_file"
                linked_skill_found=1
            fi
        done
        if [ "$linked_skill_found" -eq 0 ]; then
            ux_info "(no skills found)"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Settings Editor
# ═══════════════════════════════════════════════════════════════

claude_edit_settings() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local settings_file="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"

    if [ ! -f "$settings_file" ]; then
        ux_error "Settings file not found: $settings_file"
        return 1
    fi

    ux_header "Claude Code Settings"
    ux_info "File: $settings_file"
    ux_info ""

    ${EDITOR:-vim} "$settings_file"

    ux_info ""
    ux_success "Settings file edited"
    ux_info "Changes will take effect immediately (settings.json is symlinked)"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Marketplace Plugins Management
# ═══════════════════════════════════════════════════════════════

open_claude_plugins() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local plugins_dir="$HOME/.claude/plugins/marketplaces"

    if [ ! -d "$plugins_dir" ]; then
        ux_error "Plugins directory not found: $plugins_dir"
        ux_info "Plugins will be available after Claude Code marketplace setup"
        return 1
    fi

    ux_header "Opening Claude Marketplace Plugins"
    ux_info "Location: $plugins_dir"
    ux_info ""

    # Open in VSCode
    code "$plugins_dir"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Workflow Helpers
# ═══════════════════════════════════════════════════════════════

# Plan mode: Interactive mode (recommended)
alias clplan='claude'

# Test writing helper
cltest() {
    case "${1:-}" in "" | -h | --help)
        ux_header "cltest"
        ux_usage "cltest" "\"request\"" "Run Claude with prompt for test writing"
        ux_bullet "Example: ${UX_INFO}cltest \"Write authentication tests\"${UX_RESET}"
        [ -n "${1:-}" ] # -h/--help -> 0, no argument -> 1
        return
        ;;
    esac
    claude -p "$1"
}

# Skip permissions mode (use with caution)
clskip() {
    case "${1:-}" in "" | -h | --help)
        ux_header "clskip"
        ux_usage "clskip" "\"request\"" "Run Claude skipping permission prompts (caution)"
        ux_bullet "Example: ${UX_INFO}clskip \"Refactor this module\"${UX_RESET}"
        ux_info ""
        ux_warning "This will skip all permission prompts"
        ux_bullet "Start with small scopes and use carefully"
        [ -n "${1:-}" ] # -h/--help -> 0, no argument -> 1
        return
        ;;
    esac

    ux_warning "Running in skip permissions mode"
    ux_info "Request: $1"
    ux_info ""
    claude --dangerously-skip-permissions -p "$1"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Direct Permission Bypass Alias
# ═══════════════════════════════════════════════════════════════

alias claude-skip='claude --dangerously-skip-permissions'

# _claude_yolo_export_settings_env — propagate settings.local.json `env` block
# to the shell process so `claude` inherits it via the normal env path. Some
# Claude Code releases do not apply the settings.local.json env block to the
# spawned child, so the gateway URL / auth headers configured there silently
# never reach the request layer (symptom: `Failed to connect to
# api.anthropic.com` on a corporate-internal PC even with a fully-correct
# settings.local.json). This helper is the belt-and-suspenders fix: jq-read
# the env block and `export` each key. Idempotent, silent, no-op when jq or
# the file is missing.
#
# Parameters:
#   $1: Claude config dir (e.g. ~/.claude or ~/.claude-work)
#
# Why eval is safe here: settings.local.json is gitignored and user-owned;
# its contents are already trusted by Claude Code itself. `@sh` quoting on
# the value handles embedded newlines and shell metacharacters.
_claude_yolo_export_settings_env() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _cysee_dir="${1:-}"
    [ -n "$_cysee_dir" ] || return 0
    local _cysee_file="$_cysee_dir/settings.local.json"
    [ -f "$_cysee_file" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # Declare and assign separately to avoid SC2155 (local + command
    # substitution masks the substitution's exit status). The colleague
    # PR #576 fixed the same pattern elsewhere in setup.sh.
    local _cysee_exports
    _cysee_exports=$(jq -r '
        .env // {}
        | to_entries[]
        | "export \(.key)=\(.value | tostring | @sh)"
    ' "$_cysee_file" 2>/dev/null)

    # Explicit `return 0` — without it, the final `[ -n "" ] && ...` short-
    # circuits with exit 1 when the env block is absent / malformed, which
    # would propagate to callers expecting silent no-op.
    if [ -n "$_cysee_exports" ]; then
        eval "$_cysee_exports"
    fi
    return 0
}

# claude_yolo — 다중 계정 dispatcher (issue #287, Phase 1).
#
# Usage:
#   claude-yolo                       → CLAUDE_DEFAULT_ACCOUNT 으로 실행
#   claude-yolo --user work           → work 계정으로 실행
#   claude-yolo --user=work foo bar   → --user 추출, foo bar 는 claude 통과
#   claude-yolo -- --user not-flag    → -- 이후는 모두 claude 본체 통과
#
# 동작:
# 1. POSIX 안전 인자 재구성 (sentinel 패턴, eval 없음)
# 2. 계정 → CLAUDE_CONFIG_DIR 해석 (SSOT: _claude_resolve_account)
# 3. CLAUDE_CONFIG_DIR 환경 주입 + command claude --dangerously-skip-permissions
#
# main/master 자동 scratch/* 가드 + CLAUDE_YOLO_STAY env 는 #647 에서 제거됨 —
# 격리 워크플로는 `gwt spawn --launch --ai claude <task>` 가 SSOT.
claude_yolo() {
    _cy_account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"

    # zsh disables word-splitting; emulate sh inside this function.
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    # --user 가로채고 나머지는 위치 인자로 보존 (POSIX 안전).
    # --no-sync 는 #575 에서 skills/docs 가 디렉토리 symlink 가 되며 사라짐
    # — 쉘 시작마다 동기화할 항목이 더 이상 없다. 알 수 없는 인자는
    # claude 본체로 그대로 전달된다.
    set -- "$@" "__CY_END__"
    while [ "$1" != "__CY_END__" ]; do
        case "$1" in
            --user)
                _cy_account="$2"
                shift 2
                ;;
            --user=*)
                _cy_account="${1#--user=}"
                shift
                ;;
            *)
                set -- "$@" "$1"
                shift
                ;;
        esac
    done
    shift   # sentinel 제거

    # Internal-PC single-account override (issue #571, F-2). When
    # ~/.dotfiles-setup-mode == internal, the multi-account layout is
    # intentionally disabled — Claude Code config lives at ~/.claude/ and
    # `claude-accounts` is not in use. This branch runs BEFORE
    # _claude_resolve_account so a sandbox PC with an unset/empty
    # CLAUDE_ENABLED_ACCOUNTS can't trip the "Unknown account" path.
    if [ "$(_dotfiles_setup_mode)" = "internal" ]; then
        _cy_config_dir="$HOME/.claude"
        _cy_account="internal"
    else
        # 계정 → CONFIG_DIR (SSOT 호출)
        _cy_config_dir=$(_claude_resolve_account "$_cy_account") || {
            ux_error "Unknown account: $_cy_account"
            ux_info  "Available: $(_claude_resolve_account --list | tr '\n' ' ')"
            return 1
        }
    fi

    [ -d "$_cy_config_dir" ] || {
        ux_error "Account directory missing: $_cy_config_dir"
        ux_info  "Run: claude-accounts setup"
        return 1
    }

    # Pre-launch .claude.json integrity guard (issue #294).
    # See _claude_restore_if_reset for the heuristic and rationale.
    _claude_restore_if_reset "$_cy_config_dir"

    # Pre-launch account binding sanity (issue #300, item B).
    # Opt-in via CLAUDE_ACCOUNT_EMAIL_<account>; silent unless the mapping
    # AND a populated .claude.json AND a mismatch are all present.
    _claude_validate_login "$_cy_config_dir" "$_cy_account"

    # Apply settings.local.json env block at the shell level too — works
    # around Claude Code releases where the env block isn't propagated to
    # the spawned process. The subshell isolates exports so the caller's
    # shell env (which may persist after `claude-yolo` exits) is not
    # polluted with e.g. NODE_TLS_REJECT_UNAUTHORIZED=0.
    (
        _claude_yolo_export_settings_env "$_cy_config_dir"
        CLAUDE_CONFIG_DIR="$_cy_config_dir" command claude --dangerously-skip-permissions "$@"
    )
}

# _claude_restore_if_reset — auto-restore .claude.json from sealed snapshot
# when it has been reset to the "first-start placeholder" state (issue #294).
#
# Trigger requires ALL of:
#   1. live .claude.json exists and is < 500 bytes (healthy file is 10-100 KB)
#   2. live file contains `firstStartTime` but neither `oauthAccount` nor
#      `migrationVersion` (positive evidence of reset state, not a partial
#      write or unrelated tiny file)
#   3. .claude.json.preserved-by-migrate snapshot exists in same dir
#
# Rationale: Claude CLI sometimes rewrites .claude.json to just
# `{"firstStartTime":"..."}` on first run with a previously-unseen
# CLAUDE_CONFIG_DIR, wiping the oauth + migration cache. Since the bug is
# upstream, we can't prevent the rewrite — but we restore before the next
# launch, so the user never sees the "configuration file not found" prompt.
#
# Bypass: delete the snapshot file (`rm <dir>/.claude.json.preserved-by-migrate`)
# to opt out — useful if the user intentionally reset their config.
_claude_restore_if_reset() {
    _crir_dir="$1"
    _crir_live="$_crir_dir/.claude.json"
    _crir_snap="$_crir_dir/.claude.json.preserved-by-migrate"

    # Snapshot 부재 시에는 어느 쪽으로도 복원 불가 — silent return.
    [ -f "$_crir_snap" ] || return 0

    # Missing-case branch (issue #500, F-2): live .claude.json 자체가
    # 사라진 상태도 reset 의 한 변종으로 처리. Claude CLI 가 빈
    # CLAUDE_CONFIG_DIR 진입 시 "configuration file not found" 프롬프트를
    #띄우기 전에 sealed snapshot 으로 복원해 사용자 개입을 없앤다.
    if [ ! -f "$_crir_live" ]; then
        ux_warning "Detected missing .claude.json — restoring from sealed migrate snapshot"
        ux_info    "  → snapshot: $_crir_snap"
        if cp "$_crir_snap" "$_crir_live" 2>/dev/null; then
            _crir_restored_size=$(wc -c < "$_crir_live" 2>/dev/null | tr -d ' ')
            ux_success "  Restored $_crir_live (${_crir_restored_size:-?} bytes)"
        else
            ux_error "  Restore failed — proceeding anyway (claude may prompt for re-login)"
        fi
        return 0
    fi

    _crir_size=$(wc -c < "$_crir_live" 2>/dev/null | tr -d ' ')
    [ -n "$_crir_size" ] || return 0
    [ "$_crir_size" -lt 500 ] || return 0

    grep -q 'firstStartTime' "$_crir_live" 2>/dev/null || return 0
    grep -qE 'oauthAccount|migrationVersion' "$_crir_live" 2>/dev/null && return 0

    ux_warning "Detected reset .claude.json (${_crir_size}B, no oauth/migration cache)"
    ux_info    "  → restoring from sealed migrate snapshot: $_crir_snap"
    if cp "$_crir_snap" "$_crir_live" 2>/dev/null; then
        _crir_restored_size=$(wc -c < "$_crir_live" 2>/dev/null | tr -d ' ')
        ux_success "  Restored $_crir_live (${_crir_restored_size:-?} bytes)"
    else
        ux_error "  Restore failed — proceeding anyway (claude may prompt for re-login)"
    fi
}

alias claude-yolo='claude_yolo'

# ═══════════════════════════════════════════════════════════════
# Multi-account configuration (issue #287)
# ═══════════════════════════════════════════════════════════════

# Account resolution + auth checks live in tools/custom/lib (#2146) but stay
# shell-resident: claude_yolo needs them, and so do external callers that
# source this file (gh_pr_review.sh, herdr_pane.sh, graphify/lib.sh).
_ic_claude_lib="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/lib"
# shellcheck source=../custom/lib/claude_accounts_auth.sh
. "$_ic_claude_lib/claude_accounts_auth.sh"
unset _ic_claude_lib

# Account lifecycle and skills-dir helpers moved to tools/custom/lib (#2146) so
# interactive startup does not parse them. Each name below stays defined as a
# lazy loader: the first call sources both libs, which redefine every name
# with its real body, then re-dispatches. Keeps the public name set intact.
_claude_accounts_load() {
    _cal_lib="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/lib"
    . "$_cal_lib/claude_accounts_lifecycle.sh" && . "$_cal_lib/claude_accounts_skills.sh"
    _cal_rc=$?
    unset _cal_lib
    return "$_cal_rc"
}
for _ic_claude_fn in _claude_backup_original _claude_ensure_symlink _claude_link_lib \
    _claude_ensure_settings_copy _claude_install_herdr_hook _claude_account_setup_one \
    _claude_status_show_oauth _claude_has_unmigrated_data _claude_accounts_help \
    _claude_prepare_skills_dir _claude_prune_workspace_skills _claude_account_skill_dirs \
    _claude_under_workspace _claude_link_one _claude_link_list; do
    eval "${_ic_claude_fn}() { _claude_accounts_load && ${_ic_claude_fn} \"\$@\"; }"
done
unset _ic_claude_fn

# claude-accounts: the dispatcher stays a function (command surface + tab
# completion unchanged); the subcommand bodies run in the executable (#2146,
# command-delivery-model.md §3 — they never change the parent shell's state).
claude_accounts() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/claude_accounts.sh" "$@"
}
claude_accounts_status() { claude_accounts status "$@"; }
claude_accounts_init() { claude_accounts setup "$@"; }
claude_accounts_migrate() { claude_accounts migrate "$@"; }
claude_accounts_rollback() { claude_accounts rollback "$@"; }
claude_accounts_repair() { claude_accounts repair "$@"; }
claude_accounts_link() { claude_accounts link "$@"; }
claude_accounts_unlink() { claude_accounts unlink "$@"; }
alias claude-accounts='claude_accounts'

# _claude_yolo_register_aliases — ENABLED 계정마다 단축 alias 자동 생성.
# 매핑 SSOT (_claude_resolve_account --list) 한 곳에서 파생되므로
# 새 계정 추가 시 alias 도 자동 등장. 수동 alias 정의 금지.
_claude_yolo_register_aliases() {
    # zsh word-splitting parity (same reason as other --list consumers)
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    for _cyra_acct in $(_claude_resolve_account --list); do
        # POSIX-safe: alias 동적 생성 (eval 필요)
        # shellcheck disable=SC2139  # alias contains expanded value (intentional)
        eval "alias claude-yolo-${_cyra_acct}='claude_yolo --user ${_cyra_acct}'"
    done
}

# claude.sh 로드 시 1회 자동 호출
_claude_yolo_register_aliases
