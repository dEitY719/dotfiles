#!/bin/sh
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

# ═══════════════════════════════════════════════════════════════
# Mount management functions (loaded from shell-common/functions/mount.sh)
# ═══════════════════════════════════════════════════════════════

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

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
    local settings_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"
    local settings_target="$HOME/.claude/settings.json"
    local statusline_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/statusline-command.sh"
    local statusline_target="$HOME/.claude/statusline-command.sh"
    local skills_source_dir="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"
    local skills_target_dir="$HOME/.claude/skills"

    ux_info "Initializing Claude Code configuration..."
    echo ""

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
    elif [ -f "$settings_target" ]; then
        ux_warning "settings.json exists as regular file"
        ux_info "Backing up to settings.json.backup..."
        mv "$settings_target" "$settings_target.backup"
        ln -s "$settings_source" "$settings_target"
        ux_success "Created symbolic link for settings.json"
    else
        ln -s "$settings_source" "$settings_target"
        ux_success "Created symbolic link for settings.json"
    fi
    echo ""

    # Handle statusline-command.sh
    ux_section "Statusline Configuration"
    if [ -L "$statusline_target" ]; then
        ux_success "statusline-command.sh symbolic link already exists"
    elif [ -f "$statusline_target" ]; then
        ux_warning "statusline-command.sh exists as regular file"
        ux_info "Backing up to statusline-command.sh.backup..."
        mv "$statusline_target" "$statusline_target.backup"
        ln -s "$statusline_source" "$statusline_target"
        ux_success "Created symbolic link for statusline-command.sh"
    else
        ln -s "$statusline_source" "$statusline_target"
        ux_success "Created symbolic link for statusline-command.sh"
    fi
    echo ""

    # Handle skills directory
    ux_section "Claude Code Skills"
    skill_count=0
    if [ -d "$skills_source_dir" ]; then
        for skill_file in "$skills_source_dir"/*.md; do
            if [ -f "$skill_file" ]; then
                skill_name=$(basename "$skill_file")
                skill_target="$skills_target_dir/$skill_name"

                if [ -L "$skill_target" ]; then
                    ux_success "$skill_name (already linked)"
                elif [ -f "$skill_target" ]; then
                    ux_warning "$skill_name exists as regular file"
                    ux_info "Backing up to $skill_name.backup..."
                    mv "$skill_target" "$skill_target.backup"
                    ln -s "$skill_file" "$skill_target"
                    ux_success "$skill_name (linked)"
                else
                    ln -s "$skill_file" "$skill_target"
                    ux_success "$skill_name (linked)"
                fi
                skill_count=$((skill_count + 1))
            fi
        done

        if [ "$skill_count" -eq 0 ]; then
            ux_info "No skill files found in $skills_source_dir"
        else
            ux_success "Total: $skill_count skill(s) linked"
        fi
    else
        ux_warning "Skills source directory not found: $skills_source_dir"
    fi
    echo ""

    ux_header "Claude Code Initialization Complete"
    echo ""

    ux_section "Configuration Files"
    for config_target in "$settings_target" "$statusline_target"; do
        if [ -e "$config_target" ]; then
            ls -la -- "$config_target"
        fi
    done
    echo ""

    ux_section "Skills"
    if [ -d "$skills_target_dir" ]; then
        linked_skill_found=0
        for skill_target_file in "$skills_target_dir"/*.md; do
            if [ -e "$skill_target_file" ]; then
                ls -la -- "$skill_target_file"
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
    local settings_file="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"

    if [ ! -f "$settings_file" ]; then
        ux_error "Settings file not found: $settings_file"
        return 1
    fi

    ux_header "Claude Code Settings"
    ux_info "File: $settings_file"
    echo ""

    ${EDITOR:-vim} "$settings_file"

    echo ""
    ux_success "Settings file edited"
    ux_info "Changes will take effect immediately (settings.json is symlinked)"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Skills Directory Bind Mount
# ═══════════════════════════════════════════════════════════════

claude_mount_skills() {
    local skills_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"
    local skills_target="$HOME/.claude/skills"

    # Check if source directory exists
    if [ ! -d "$skills_source" ]; then
        return 0
    fi

    # Create target directory if not exists
    if [ ! -d "$skills_target" ]; then
        mkdir -p "$skills_target"
    fi

    # Check if already mounted (using unified _is_mounted function if available)
    if declare -f _is_mounted >/dev/null 2>&1; then
        _is_mounted "$skills_target" && return 0
    else
        # Fallback: Check if already mounted using findmnt
        if command -v findmnt > /dev/null 2>&1; then
            findmnt "$skills_target" > /dev/null 2>&1 && return 0
        else
            # Final fallback to mount command
            mount | grep -q "on ${skills_target} " && return 0
        fi
    fi

    # Perform bind mount (will prompt for sudo password if needed)
    if sudo mount --bind "$skills_source" "$skills_target" 2>/dev/null; then
        return 0
    else
        # Silent fail - don't spam errors on every shell startup
        return 1
    fi
}

# NOTE: Auto-mount functionality removed from shell init to prevent sudo prompts
# during shell startup. Use explicit functions instead:
#   claude_mount_skills   - Mount skills directory
#   claude_mount_docs     - Mount docs directory

# ═══════════════════════════════════════════════════════════════
# Claude Code Documentation Directory Bind Mount
# ═══════════════════════════════════════════════════════════════

claude_mount_docs() {
    local docs_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/docs"
    local docs_target="$HOME/.claude/docs"

    # Check if source directory exists
    if [ ! -d "$docs_source" ]; then
        return 0
    fi

    # Create target directory if not exists
    if [ ! -d "$docs_target" ]; then
        mkdir -p "$docs_target"
    fi

    # Check if already mounted (using unified _is_mounted function if available)
    if declare -f _is_mounted >/dev/null 2>&1; then
        _is_mounted "$docs_target" && return 0
    else
        # Fallback: Check if already mounted using findmnt
        if command -v findmnt > /dev/null 2>&1; then
            findmnt "$docs_target" > /dev/null 2>&1 && return 0
        else
            # Final fallback to mount command
            mount | grep -q "on ${docs_target} " && return 0
        fi
    fi

    # Perform bind mount (will prompt for sudo password if needed)
    if sudo mount --bind "$docs_source" "$docs_target" 2>/dev/null; then
        return 0
    else
        # Silent fail - don't spam errors on every shell startup
        return 1
    fi
}

# NOTE: Auto-mount is controlled by environment variables:
#   CLAUDE_AUTO_MOUNT_SKILLS=1
#   CLAUDE_AUTO_MOUNT_DOCS=1
# This repository sets defaults in shell-common/env/claude.sh.
# Requires passwordless sudoers configured by dotfiles/claude/setup.sh

# ═══════════════════════════════════════════════════════════════
# Claude Code Mount All Helper
# ═══════════════════════════════════════════════════════════════

# Mount all Claude directories at once (for manual initialization)
claude_mount_all() {
    ux_header "Claude Code Directory Mounts"

    local mounted_count=0
    local failed_count=0

    # Try mounting skills
    ux_info "Mounting skills directory..."
    if claude_mount_skills; then
        ux_success "skills directory mounted"
        mounted_count=$((mounted_count + 1))
    else
        ux_warning "skills directory mount failed or already mounted"
        failed_count=$((failed_count + 1))
    fi

    # Try mounting docs
    ux_info "Mounting docs directory..."
    if claude_mount_docs; then
        ux_success "docs directory mounted"
        mounted_count=$((mounted_count + 1))
    else
        ux_warning "docs directory mount failed or already mounted"
        failed_count=$((failed_count + 1))
    fi

    echo ""
    ux_section "Summary"
    echo "Successfully mounted: $mounted_count"
    echo "Failed or already mounted: $failed_count"
}

alias claude-mount-all='claude_mount_all'
alias claude-mount-skills='claude_mount_skills'
alias claude-mount-docs='claude_mount_docs'

# Auto-mount configuration via environment variables
# Set to "1" to enable auto-mounting in interactive shells
# Example: export CLAUDE_AUTO_MOUNT_SKILLS=1
_claude_try_auto_mount() {
    case "$-" in
        *i*) ;;
        *) return 0 ;;
    esac

    if [ "${CLAUDE_AUTO_MOUNT_SKILLS:-0}" = "1" ]; then
        claude_mount_skills >/dev/null 2>&1 || true
    fi

    if [ "${CLAUDE_AUTO_MOUNT_DOCS:-0}" = "1" ]; then
        claude_mount_docs >/dev/null 2>&1 || true
    fi
}

_claude_try_auto_mount

# ═══════════════════════════════════════════════════════════════
# Claude Code Marketplace Plugins Management
# ═══════════════════════════════════════════════════════════════

open_claude_plugins() {
    local plugins_dir="$HOME/.claude/plugins/marketplaces"

    if [ ! -d "$plugins_dir" ]; then
        ux_error "Plugins directory not found: $plugins_dir"
        ux_info "Plugins will be available after Claude Code marketplace setup"
        return 1
    fi

    ux_header "Opening Claude Marketplace Plugins"
    ux_info "Location: $plugins_dir"
    echo ""

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
    if [ -z "$1" ]; then
        ux_header "cltest"
        ux_usage "cltest" "\"request\"" "Run Claude with prompt for test writing"
        ux_bullet "Example: ${UX_INFO}cltest \"Write authentication tests\"${UX_RESET}"
        return 1
    fi
    claude -p "$1"
}

# Skip permissions mode (use with caution)
clskip() {
    if [ -z "$1" ]; then
        ux_header "clskip"
        ux_usage "clskip" "\"request\"" "Run Claude skipping permission prompts (caution)"
        ux_bullet "Example: ${UX_INFO}clskip \"Refactor this module\"${UX_RESET}"
        echo ""
        ux_warning "This will skip all permission prompts"
        ux_bullet "Start with small scopes and use carefully"
        return 1
    fi

    ux_warning "Running in skip permissions mode"
    ux_info "Request: $1"
    echo ""
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
# api.anthropic.com` on a Samsung-internal PC even with a fully-correct
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
# 3. main/master 브랜치 가드 (기존 동작 유지) — bypass: CLAUDE_YOLO_STAY=1
# 4. CLAUDE_CONFIG_DIR 환경 주입 + command claude --dangerously-skip-permissions
claude_yolo() {
    _cy_account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"
    _cy_no_sync=0

    # zsh disables word-splitting; emulate sh inside this function.
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    # --user / --no-sync 가로채고 나머지는 위치 인자로 보존 (POSIX 안전)
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
            --no-sync)
                _cy_no_sync=1
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

    # main/master 브랜치 가드 (기존 로직 보존)
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _cy_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
        case "$_cy_branch" in
            main|master)
                if [ -z "${CLAUDE_YOLO_STAY:-}" ]; then
                    _cy_new_branch="scratch/$(date +%m%d-%H%M%S)"
                    ux_warning "main 브랜치 감지 → ${_cy_new_branch} 로 전환 (bypass: CLAUDE_YOLO_STAY=1)"
                    git switch -c "$_cy_new_branch" || return 1
                fi
                ;;
        esac
    fi

    # Pre-launch .claude.json integrity guard (issue #294).
    # See _claude_restore_if_reset for the heuristic and rationale.
    _claude_restore_if_reset "$_cy_config_dir"

    # Pre-launch account binding sanity (issue #300, item B).
    # Opt-in via CLAUDE_ACCOUNT_EMAIL_<account>; silent unless the mapping
    # AND a populated .claude.json AND a mismatch are all present.
    _claude_validate_login "$_cy_config_dir" "$_cy_account"

    # Pre-launch skills/docs sync (issue #342). Silent when in-sync; emits
    # one line per action when something changed (so the user sees newly
    # added skills landing without having to run `claude-accounts
    # skills-sync` themselves). Opt out with `claude-yolo --no-sync ...`.
    if [ "$_cy_no_sync" = "0" ]; then
        CLAUDE_SKILLS_SYNC_QUIET=1 claude_skills_sync || true
    fi

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

# _claude_validate_login — expected ↔ actual oauth email check (issue #300-B).
#
# Catches the "wrong Google account on browser" trap: a leftover personal
# Google session bleeds into the OAuth flow for `claude-yolo --user work`,
# leaving the work CLAUDE_CONFIG_DIR populated with personal credentials.
# The code in this repo can't influence the browser, but it CAN cross-check
# the resulting .claude.json against an expected email and warn loudly so
# the user can recover before the misbinding becomes load-bearing.
#
# Opt-in: caller defines `CLAUDE_ACCOUNT_EMAIL_<account>` (e.g.
# `CLAUDE_ACCOUNT_EMAIL_work=alice@corp.com`) in claude.local.sh. Without
# the mapping the function silently returns — zero-config / zero-regression
# for everyone who doesn't opt in.
_claude_validate_login() {
    _cvl_dir="$1"
    _cvl_acct="$2"

    _cvl_expected=$(_claude_expected_email "$_cvl_acct")
    [ -n "$_cvl_expected" ] || return 0

    _cvl_json="$_cvl_dir/.claude.json"
    [ -f "$_cvl_json" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    _cvl_actual=$(jq -r '.oauthAccount?.emailAddress? // empty' "$_cvl_json" 2>/dev/null)
    [ -n "$_cvl_actual" ] || return 0
    [ "$_cvl_expected" = "$_cvl_actual" ] && return 0

    ux_warning "Account mismatch on '$_cvl_acct':"
    ux_warning "  expected: $_cvl_expected (CLAUDE_ACCOUNT_EMAIL_${_cvl_acct})"
    ux_warning "  actual:   $_cvl_actual (.claude.json oauthAccount)"
    ux_info    "  → 다른 Google 계정으로 잘못 로그인된 자격증명일 수 있습니다."
    ux_info    "  → 복구: rm '$_cvl_dir/.credentials.json' '$_cvl_json' && claude-yolo --user $_cvl_acct"
}
alias claude-yolo='claude_yolo'

# ═══════════════════════════════════════════════════════════════
# Multi-account configuration (issue #287)
# ═══════════════════════════════════════════════════════════════

# _dotfiles_setup_mode — read ~/.dotfiles-setup-mode and canonicalise.
#
# Returns one of: public | internal | external | "" (file missing).
# Legacy numeric values ("1|2|3") written by older shell-common/setup.sh
# (pre-#571) are translated to their symbolic equivalents, so users
# don't hit a wedge after upgrading. Empty when the file doesn't exist
# (fresh install before setup.sh has run).
#
# Used by claude_yolo (F-2) to bypass multi-account resolution and by
# claude_accounts_rollback (F-3) to confirm the rollback target.
_dotfiles_setup_mode() {
    _dsm_file="$HOME/.dotfiles-setup-mode"
    [ -f "$_dsm_file" ] || { echo ""; return 0; }
    _dsm_raw=$(tr -d ' \t\n\r' < "$_dsm_file" 2>/dev/null)
    case "$_dsm_raw" in
        1|public)   echo "public" ;;
        2|internal) echo "internal" ;;
        3|external) echo "external" ;;
        *)          echo "$_dsm_raw" ;;
    esac
}

# _claude_resolve_account — 계정 매핑 SSOT (convention-based, issue #568).
# Usage:
#   _claude_resolve_account <name>     → echo "$HOME/.claude-<name>" when
#                                        <name> is in CLAUDE_ENABLED_ACCOUNTS
#                                        and passes the safe-identifier
#                                        regex. return 1 otherwise.
#   _claude_resolve_account --list     → echo ENABLED accounts (one per line)
#                                        that pass the safe-identifier regex.
#   _claude_resolve_account --list-all → deprecated; same as --list. Kept
#                                        for back-compat with external
#                                        scripts that may still call it.
#
# 새 계정 추가 = claude.local.sh 의 CLAUDE_ENABLED_ACCOUNTS 에 단어 추가
# 만으로 끝. 코드 수정 불필요. 디렉터리는 자동으로 ~/.claude-<name>.
#
# Safe-identifier regex: ^[a-z][a-z0-9_-]*$
# - 첫 글자 소문자, 뒤로 소문자·숫자·하이픈·언더스코어.
# - alias 명·env-var 접미사·디렉터리명 셋 다 안전하게 쓰일 식별자.
_claude_resolve_account() {
    # zsh disables word-splitting by default; emulate sh inside this function
    # so `for x in $LIST` behaves identically to bash/dash. (See MEMORY.md
    # "Zsh-Specific Tracing Behavior" for the same pattern in gcp_scan.sh.)
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    case "$1" in
        --list|--list-all)
            # --list-all 은 issue #568 에서 --list 로 통합. 외부 사용자
            # 보호용 호환 alias — 향후 메이저 버전에서 제거 가능.
            # 검증을 인라인으로 — 재귀 호출 시 ENABLED 가 "--list" 같은
            # 플래그 토큰을 포함하면 무한 재귀에 빠질 수 있고, 재귀는
            # O(N²) 비용을 만든다 (gemini review on PR #569).
            # ${VAR:-} 로 set -u 환경에서 unbound 회피.
            # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
            for _cra_acct in ${CLAUDE_ENABLED_ACCOUNTS:-}; do
                case "$_cra_acct" in
                    [a-z]*) ;;
                    *) continue ;;
                esac
                case "$_cra_acct" in
                    *[!a-z0-9_-]*) continue ;;
                esac
                echo "$_cra_acct"
            done
            return 0
            ;;
    esac

    # name validation: must start with lowercase letter, rest [a-z0-9_-]
    case "$1" in
        [a-z]*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!a-z0-9_-]*) return 1 ;;
    esac

    # ENABLED whitelist check — unknown names fail even if regex-valid.
    # Preserves the "Unknown account: xyz" path in claude_yolo for typos.
    # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
    for _cra_acct in ${CLAUDE_ENABLED_ACCOUNTS:-}; do
        if [ "$_cra_acct" = "$1" ]; then
            echo "$HOME/.claude-$1"
            return 0
        fi
    done
    return 1
}

# _claude_expected_email <account-name> — expected oauth email lookup.
# Reads CLAUDE_ACCOUNT_EMAIL_<account> if defined, else echoes nothing.
# Opt-in mapping convention from issue #300, items B and C — kept in a
# helper so claude_yolo and claude_accounts_status share the same source
# of truth.
#
# Uses eval (not ${!var}) for POSIX sh portability — the input is always
# an account name vetted by _claude_resolve_account, so injection is not
# a concern.
_claude_expected_email() {
    _ceeem_acct="$1"
    [ -n "$_ceeem_acct" ] || return 0
    eval "echo \"\${CLAUDE_ACCOUNT_EMAIL_${_ceeem_acct}:-}\""
}

# _claude_ensure_symlink — 멱등 symlink 생성.
# - 없음 → 생성
# - 같은 target 의 symlink → skip (출력 "already")
# - 다른 file/dir → timestamped backup 후 재생성
_claude_ensure_symlink() {
    _ces_src="$1"
    _ces_tgt="$2"

    if [ -L "$_ces_tgt" ]; then
        _ces_current=$(readlink "$_ces_tgt")
        if [ "$_ces_current" = "$_ces_src" ]; then
            ux_info "  ✓ already linked: $_ces_tgt"
            return 0
        fi
        ux_warning "  symlink target mismatch — recreating: $_ces_tgt"
        rm "$_ces_tgt"
    elif [ -e "$_ces_tgt" ]; then
        # Backup naming matches claude/setup.sh:100 legacy convention
        # so users with a mixed-version setup see one consistent format.
        _ces_backup="${_ces_tgt}-$(date +%Y%m%d%H%M%S)-original"
        ux_warning "  backing up existing file: $_ces_tgt → $_ces_backup"
        mv "$_ces_tgt" "$_ces_backup"
    fi

    ln -s "$_ces_src" "$_ces_tgt"
    ux_success "  created symlink: $_ces_tgt → $_ces_src"
}

# _claude_ensure_bind_mount — 멱등 bind mount.
# - 이미 마운트됨 → skip
# - 안 됨 → sudo mount --bind (sudoers 등록 전제)
_claude_ensure_bind_mount() {
    _cebm_src="$1"
    _cebm_tgt="$2"

    [ -d "$_cebm_src" ] || {
        ux_warning "  bind mount source missing: $_cebm_src"
        return 1
    }

    mkdir -p "$_cebm_tgt"

    if _is_mounted "$_cebm_tgt"; then
        ux_info "  ✓ already mounted: $_cebm_tgt"
        return 0
    fi

    if sudo mount --bind "$_cebm_src" "$_cebm_tgt" 2>/dev/null; then
        ux_success "  bind mount: $_cebm_tgt ← $_cebm_src"
    else
        ux_error "  bind mount failed: $_cebm_tgt (check sudoers)"
        return 1
    fi
}

# _claude_dir_sync_one — per-account, per-dir symlink sync (issue #342).
#
# Replaces the bind-mount design: each SSOT entry under
# "${DOTFILES_ROOT}/claude/<name>" gets an individual symlink under
# "<cdir>/<name>/<entry>". No sudo, persists across reboot, drift visible
# via plain `ls -la` / `find -type l`.
#
# Args: <cdir> <name>   e.g. "$HOME/.claude-personal" "skills"
#
# Behavior (idempotent):
# 1. Each SSOT entry → ensured as symlink. Real-dir collision → backed up
#    to "<cdir>/.sync-backup/<name>/<entry>-pre-sync-<TS>". Stale symlink
#    (wrong target) → replaced.
# 2. Orphan cleanup: entries in target with no SSOT match. Symlinks →
#    auto-removed. Real dirs → backed up to
#    "<cdir>/.sync-backup/<name>/<entry>-orphan-<TS>" (never auto-deleted;
#    preserves any user data the user dropped here).
# 3. Pre-step migration: any pre-existing legacy backup at
#    "<cdir>/<name>/*-pre-sync-*" / "*-orphan-*" (created by older
#    versions of this function) is moved to "<cdir>/.sync-backup/<name>/"
#    so the Claude Code skill scanner stops indexing backups as skills
#    (issue #344). Idempotent — no-op once migrated.
#
# Backup location rationale (issue #344): the Claude Code skill scanner
# treats every directory under "<cdir>/skills/" as a skill candidate, so
# placing backups inside "<cdir>/skills/" caused duplicate skills like
# "cli-dev" + "cli-dev-pre-sync-<TS>" to appear in available-skills.
# "<cdir>/.sync-backup/<name>/" sits outside the scanner's view while
# remaining co-located for easy `ls`-driven discovery.
#
# Side effect (return globals — POSIX sh has no array returns):
#   _CLAUDE_DIR_SYNC_LAST_CHANGED — number of mutating actions
#   _CLAUDE_DIR_SYNC_LAST_LINKED  — symlinks pointing at correct SSOT entry
#   _CLAUDE_DIR_SYNC_LAST_SOURCE  — total SSOT entries
#
# Silent (no output) when fully in-sync. Otherwise emits one line per action.
_claude_dir_sync_one() {
    _cdso_cdir="$1"
    _cdso_name="$2"
    # Fallback parity with claude_mount_skills/claude_init in this file: if
    # the function is invoked before the dotfiles env loader runs (or in a
    # crippled login shell), don't construct paths starting at /.
    _cdso_src_root="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/$_cdso_name"
    _cdso_tgt_root="$_cdso_cdir/$_cdso_name"
    _cdso_backup_root="$_cdso_cdir/.sync-backup/$_cdso_name"
    _CLAUDE_DIR_SYNC_LAST_CHANGED=0
    _CLAUDE_DIR_SYNC_LAST_LINKED=0
    _CLAUDE_DIR_SYNC_LAST_SOURCE=0

    if [ ! -d "$_cdso_src_root" ]; then
        return 0
    fi

    mkdir -p "$_cdso_tgt_root"
    _cdso_ts=$(date +%Y%m%d%H%M%S)

    # Pre-step: migrate legacy backups out of the scanner's view (issue #344).
    # Older versions placed *-pre-sync-* / *-orphan-* directly under
    # "<cdir>/<name>/", which Claude Code indexed as duplicate skills.
    # Idempotent: only moves entries that still live in the legacy location.
    for _cdso_legacy in "$_cdso_tgt_root"/*-pre-sync-* "$_cdso_tgt_root"/*-orphan-*; do
        [ -e "$_cdso_legacy" ] || [ -L "$_cdso_legacy" ] || continue
        mkdir -p "$_cdso_backup_root"
        _cdso_legacy_name=$(basename "$_cdso_legacy")
        if mv "$_cdso_legacy" "$_cdso_backup_root/$_cdso_legacy_name"; then
            ux_info "  $_cdso_name/$_cdso_legacy_name: migrated legacy backup → .sync-backup/$_cdso_name/"
            _CLAUDE_DIR_SYNC_LAST_CHANGED=$((_CLAUDE_DIR_SYNC_LAST_CHANGED + 1))
        fi
    done

    # Pass 1: ensure each SSOT entry has matching symlink
    for _cdso_src in "$_cdso_src_root"/*/; do
        [ -d "$_cdso_src" ] || continue
        _cdso_basename=$(basename "$_cdso_src")
        _CLAUDE_DIR_SYNC_LAST_SOURCE=$((_CLAUDE_DIR_SYNC_LAST_SOURCE + 1))
        _cdso_src_canon="$_cdso_src_root/$_cdso_basename"
        _cdso_tgt="$_cdso_tgt_root/$_cdso_basename"

        if [ -L "$_cdso_tgt" ]; then
            _cdso_current=$(readlink "$_cdso_tgt")
            if [ "$_cdso_current" = "$_cdso_src_canon" ]; then
                _CLAUDE_DIR_SYNC_LAST_LINKED=$((_CLAUDE_DIR_SYNC_LAST_LINKED + 1))
                continue
            fi
            ux_info "  $_cdso_name/$_cdso_basename: replacing stale symlink"
            rm "$_cdso_tgt"
        elif [ -e "$_cdso_tgt" ]; then
            mkdir -p "$_cdso_backup_root"
            _cdso_backup="$_cdso_backup_root/${_cdso_basename}-pre-sync-${_cdso_ts}"
            ux_warning "  $_cdso_name/$_cdso_basename: backing up real dir → .sync-backup/$_cdso_name/$(basename "$_cdso_backup")"
            mv "$_cdso_tgt" "$_cdso_backup"
        fi

        if ln -s "$_cdso_src_canon" "$_cdso_tgt"; then
            ux_success "  $_cdso_name/$_cdso_basename: linked"
            _CLAUDE_DIR_SYNC_LAST_LINKED=$((_CLAUDE_DIR_SYNC_LAST_LINKED + 1))
            _CLAUDE_DIR_SYNC_LAST_CHANGED=$((_CLAUDE_DIR_SYNC_LAST_CHANGED + 1))
        else
            ux_error "  $_cdso_name/$_cdso_basename: ln -s failed"
        fi
    done

    # Pass 2: orphan cleanup — entries in target that no longer match SSOT.
    # The *-pre-sync-* / *-orphan-* skip is defensive: backups now live in
    # .sync-backup/<name>/ (issue #344) so should never appear here, but
    # the guard remains in case a leftover somehow lands in the scan dir.
    for _cdso_entry in "$_cdso_tgt_root"/*; do
        [ -e "$_cdso_entry" ] || [ -L "$_cdso_entry" ] || continue
        _cdso_ename=$(basename "$_cdso_entry")
        case "$_cdso_ename" in
            *-pre-sync-*|*-orphan-*) continue ;;
        esac
        [ -d "$_cdso_src_root/$_cdso_ename" ] && continue

        if [ -L "$_cdso_entry" ]; then
            if rm "$_cdso_entry"; then
                ux_info "  $_cdso_name/$_cdso_ename: removed orphan symlink"
                _CLAUDE_DIR_SYNC_LAST_CHANGED=$((_CLAUDE_DIR_SYNC_LAST_CHANGED + 1))
            fi
        else
            mkdir -p "$_cdso_backup_root"
            _cdso_obackup="$_cdso_backup_root/${_cdso_ename}-orphan-${_cdso_ts}"
            if mv "$_cdso_entry" "$_cdso_obackup"; then
                ux_warning "  $_cdso_name/$_cdso_ename: orphan dir → .sync-backup/$_cdso_name/$(basename "$_cdso_obackup")"
                _CLAUDE_DIR_SYNC_LAST_CHANGED=$((_CLAUDE_DIR_SYNC_LAST_CHANGED + 1))
            fi
        fi
    done
}

# _claude_count_dir_sync — print "<linked>|<source>" counts for one
# account/dirname. Used by claude_accounts_status to display drift ratio.
# Read-only; never mutates.
_claude_count_dir_sync() {
    _ccds_cdir="$1"
    _ccds_name="$2"
    # Same fallback as _claude_dir_sync_one — must agree, otherwise the
    # ratio would lie about a sync that did happen.
    _ccds_src_root="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/$_ccds_name"
    _ccds_tgt_root="$_ccds_cdir/$_ccds_name"

    _ccds_source=0
    if [ -d "$_ccds_src_root" ]; then
        for _ccds_s in "$_ccds_src_root"/*/; do
            [ -d "$_ccds_s" ] || continue
            _ccds_source=$((_ccds_source + 1))
        done
    fi

    _ccds_linked=0
    if [ -d "$_ccds_tgt_root" ]; then
        for _ccds_t in "$_ccds_tgt_root"/*; do
            [ -L "$_ccds_t" ] || continue
            _ccds_n=$(basename "$_ccds_t")
            [ -d "$_ccds_src_root/$_ccds_n" ] || continue
            _ccds_real=$(readlink "$_ccds_t")
            if [ "$_ccds_real" = "$_ccds_src_root/$_ccds_n" ]; then
                _ccds_linked=$((_ccds_linked + 1))
            fi
        done
    fi

    echo "$_ccds_linked|$_ccds_source"
}

# claude_skills_sync — public entry: sync skills + docs across all enabled
# accounts via per-skill symlinks. Replaces the legacy bind-mount approach
# (issue #342). Idempotent — second run reports "no changes".
#
# Quiet mode: set CLAUDE_SKILLS_SYNC_QUIET=1 to suppress header/summary
# (per-action output is preserved so changes remain visible).
claude_skills_sync() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    if [ -z "${CLAUDE_SKILLS_SYNC_QUIET:-}" ]; then
        ux_header "Claude Skills Sync"
    fi

    _css_total=0
    for _css_acct in $(_claude_resolve_account --list); do
        _css_cdir=$(_claude_resolve_account "$_css_acct")
        [ -d "$_css_cdir" ] || continue

        if [ -z "${CLAUDE_SKILLS_SYNC_QUIET:-}" ]; then
            ux_section "Account: $_css_acct ($_css_cdir)"
        fi

        _claude_dir_sync_one "$_css_cdir" skills
        _css_total=$((_css_total + _CLAUDE_DIR_SYNC_LAST_CHANGED))
        _claude_dir_sync_one "$_css_cdir" docs
        _css_total=$((_css_total + _CLAUDE_DIR_SYNC_LAST_CHANGED))
    done

    if [ "$_css_total" -eq 0 ]; then
        if [ -z "${CLAUDE_SKILLS_SYNC_QUIET:-}" ]; then
            ux_info "(no changes — skills/docs already in sync)"
        fi
    else
        ux_success "skills/docs sync: $_css_total change(s)"
    fi
    return 0
}
alias claude-skills-sync='claude_skills_sync'

# _claude_account_setup_one — 단일 계정의 link/sync 멱등 셋업.
_claude_account_setup_one() {
    _caso_acct="$1"
    _caso_cdir="$2"
    ux_section "Account: $_caso_acct ($_caso_cdir)"

    mkdir -p "$_caso_cdir"
    mkdir -p "$_caso_cdir/projects/GLOBAL"

    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/settings.json"          "$_caso_cdir/settings.json"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/settings.local.json"    "$_caso_cdir/settings.local.json"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/statusline-command.sh"  "$_caso_cdir/statusline-command.sh"
    _claude_ensure_symlink "$HOME/.claude-shared/plugins"                   "$_caso_cdir/plugins"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/global-memory"          "$_caso_cdir/projects/GLOBAL/memory"

    # Per-skill / per-doc symlinks (issue #342). Replaces the legacy bind
    # mount: no sudo, persists across reboot, no silent regression when
    # mount drops. CLAUDE_SKIP_BIND_MOUNT is preserved as a no-op for
    # backward compat with existing test harnesses.
    _claude_dir_sync_one "$_caso_cdir" skills
    _claude_dir_sync_one "$_caso_cdir" docs
}

# _claude_status_show_oauth — append OAuth binding (email/org) to the
# Credentials line in claude_accounts_status (issue #300, item C).
#
# Visibility goal: the status command already says "✓ logged in" but does
# not say *which* Anthropic account those credentials map to. Without
# that, item-B's misbinding trap is invisible at diagnosis time. This
# helper jq-extracts the .oauthAccount fields populated by Claude after
# its first authenticated call, and prints two indented lines.
#
# Silent skip when: .claude.json missing, jq missing, or oauthAccount
# field absent (e.g. first-start placeholder before login completes).
# When item-B's expected mapping is also defined and disagrees with the
# observed email, append a ⚠️ marker to make the discrepancy obvious.
_claude_status_show_oauth() {
    _csso_dir="$1"
    _csso_acct="$2"
    _csso_json="$_csso_dir/.claude.json"

    [ -f "$_csso_json" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # Single jq invocation (was 3 separate forks — claude_accounts_status
    # iterates per account so the saving compounds). `|` delimiter chosen
    # because the gemini-suggested space form breaks on real-world
    # organizationName values that contain spaces (observed: "★ S.LSI AX
    # Agent ★"). POSIX heredoc — no bash process substitution.
    _csso_blob=$(jq -r '"\(.oauthAccount?.emailAddress? // "")|\(.oauthAccount?.organizationName? // "")|\(.oauthAccount?.organizationType? // "")"' "$_csso_json" 2>/dev/null)
    IFS='|' read -r _csso_email _csso_org _csso_type <<EOF
$_csso_blob
EOF
    [ -n "$_csso_email" ] || return 0

    _csso_marker=""
    _csso_expected=$(_claude_expected_email "$_csso_acct")
    if [ -n "$_csso_expected" ] && [ "$_csso_expected" != "$_csso_email" ]; then
        _csso_marker=" ⚠️  expected $_csso_expected"
    fi

    echo "    └─ Email: $_csso_email$_csso_marker"
    if [ -n "$_csso_org" ]; then
        if [ -n "$_csso_type" ]; then
            echo "    └─ Org:   $_csso_org ($_csso_type)"
        else
            echo "    └─ Org:   $_csso_org"
        fi
    fi
}

# claude_accounts_status — 진단 출력 (모든 ENABLED 계정의 상태).
claude_accounts_status() {
    ux_header "Claude Accounts Status"
    ux_info "Default: $CLAUDE_DEFAULT_ACCOUNT"
    ux_info "Enabled: $CLAUDE_ENABLED_ACCOUNTS"
    if [ -d "$HOME/.claude-shared/plugins" ]; then
        ux_info "Shared:  $HOME/.claude-shared/plugins ✓"
    else
        ux_warning "Shared:  $HOME/.claude-shared/plugins ✗ missing"
    fi
    echo ""

    # zsh word-splitting parity
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    for _cas_acct in $(_claude_resolve_account --list); do
        _cas_cdir=$(_claude_resolve_account "$_cas_acct")
        ux_section "Account: $_cas_acct"
        if [ -d "$_cas_cdir" ]; then
            echo "  Path:        $_cas_cdir ✓ exists"
        else
            echo "  Path:        $_cas_cdir ✗ missing"
        fi

        if [ -f "$_cas_cdir/.credentials.json" ]; then
            echo "  Credentials: .credentials.json ✓ logged in"
            _claude_status_show_oauth "$_cas_cdir" "$_cas_acct"
        else
            echo "  Credentials: .credentials.json ✗ NOT logged in"
            echo "                → Run: claude-yolo --user $_cas_acct"
        fi

        for _cas_link in settings.json settings.local.json statusline-command.sh plugins projects/GLOBAL/memory; do
            if [ -L "$_cas_cdir/$_cas_link" ]; then
                echo "  $_cas_link: symlink ✓"
            else
                echo "  $_cas_link: ✗ missing"
            fi
        done

        # Skills/docs sync ratio (issue #342) — replaces the legacy bind
        # mount status. `linked/source ✓` when fully synced, `(drift)`
        # marker + recovery hint when partial.
        for _cas_dir in skills docs; do
            _cas_ratio=$(_claude_count_dir_sync "$_cas_cdir" "$_cas_dir")
            _cas_linked=${_cas_ratio%|*}
            _cas_source=${_cas_ratio#*|}
            if [ "$_cas_source" -eq 0 ]; then
                echo "  $_cas_dir: source missing ✗"
            elif [ "$_cas_linked" -eq "$_cas_source" ]; then
                echo "  $_cas_dir: $_cas_linked/$_cas_source ✓"
            else
                echo "  $_cas_dir: $_cas_linked/$_cas_source ⚠️  (run: claude-accounts skills-sync)"
            fi
        done
        echo ""
    done
}

# _claude_has_unmigrated_data — SSOT for "user has legacy ~/.claude data
# that must be migrated before setup". Used by claude_accounts_init AND
# claude/setup.sh — keeping the sentinel list in one place.
# Returns 0 (true) if migration is needed, 1 (false) otherwise.
# Tolerates empty bind-mount leftovers (skills/, docs/) — those are not
# user data, just unmounted dirs from the legacy layout.
#
# Migration-done check iterates CLAUDE_ENABLED_ACCOUNTS (issue #568) so
# adding work1 / work-eng / etc. via env doesn't need a code edit here.
_claude_has_unmigrated_data() {
    [ -d "$HOME/.claude" ] || return 1

    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi
    # ${VAR:-} for set -u safety (gemini review on PR #569).
    # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
    for _chud_acct in ${CLAUDE_ENABLED_ACCOUNTS:-}; do
        [ -d "$HOME/.claude-$_chud_acct" ] && return 1
    done

    [ -e "$HOME/.claude/.credentials.json" ] && return 0
    [ -d "$HOME/.claude/projects" ] && return 0
    [ -d "$HOME/.claude/sessions" ] && return 0
    [ -e "$HOME/.claude/history.jsonl" ] && return 0
    [ -d "$HOME/.claude/plugins" ] && return 0
    return 1
}

# claude_accounts_init — 멱등 setup, 3대 PC 공통 진입점.
claude_accounts_init() {
    ux_header "Claude Accounts Setup"

    # Unmigrated guard runs BEFORE any mkdir, so a stale ~/.claude/ from
    # another tool can't be silently obscured by guard-dir creation.
    if _claude_has_unmigrated_data; then
        ux_warning "$HOME/.claude/ 에 기존 사용자 데이터가 있습니다."
        ux_info    "먼저 마이그레이션을 실행하세요: claude-accounts migrate"
        return 1
    fi

    mkdir -p "$HOME/.claude-shared/plugins"
    mkdir -p "$HOME/.claude"

    # zsh word-splitting parity (same reason as _claude_resolve_account)
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    for _cai_acct in $(_claude_resolve_account --list); do
        _cai_cdir=$(_claude_resolve_account "$_cai_acct")
        _claude_account_setup_one "$_cai_acct" "$_cai_cdir"
    done

    ux_success "All accounts ready"
}

# claude_accounts_migrate — 1회 마이그레이션 (Home-PC 등 기존 데이터
# 보유 PC 한정). 멱등: 이미 마이그됐으면 즉시 skip.
claude_accounts_migrate() {
    if [ -d "$HOME/.claude-personal" ]; then
        ux_info "Already migrated to ~/.claude-personal — skipping"
        return 0
    fi

    if [ ! -d "$HOME/.claude" ]; then
        ux_info "$HOME/.claude not found — nothing to migrate. Run: claude-accounts setup"
        return 0
    fi

    # Diagnostic: capture .claude.json size BEFORE the mv (issue #294).
    # If the file is already in the "first-start placeholder" state at this
    # point, the regression is upstream of migrate (bad shutdown, prior
    # corruption) — and the post-mv size check below will match.
    _cam_pre_size=""
    if [ -f "$HOME/.claude/.claude.json" ]; then
        _cam_pre_size=$(wc -c < "$HOME/.claude/.claude.json" 2>/dev/null | tr -d ' ')
        ux_info "Pre-migrate ~/.claude/.claude.json size: ${_cam_pre_size:-?} bytes"
        if [ -n "$_cam_pre_size" ] && [ "$_cam_pre_size" -lt 500 ]; then
            ux_warning "  .claude.json is suspiciously small (< 500B) — already in"
            ux_warning "  first-start placeholder state. Migration will preserve it"
            ux_warning "  as-is, but you may need to re-login on first use."
        fi
    else
        # Issue #500, F-3: pre-migrate .claude.json missing means we cannot
        # seal a snapshot, so _claude_restore_if_reset cannot auto-recover
        # later. Surface that fact up front so the user knows a manual
        # re-login may be required after the first claude-yolo run.
        # English wording + ux_info for the explanatory follow-up matches
        # the surrounding _cam_pre_size block (PR #503 review).
        ux_warning "Pre-migrate ~/.claude/.claude.json missing — sealed snapshot not created"
        ux_info    "  Automatic restoration will be unavailable if .claude.json is reset"
        ux_info    "  (manual re-login required: re-run claude-yolo after first login)"
    fi

    ux_warning "Will move ~/.claude → ~/.claude-personal"
    ux_info    "Preserves: credentials, sessions, projects, history"
    printf "Continue? (y/N): "
    read -r _cam_reply
    if [ "$_cam_reply" != "y" ] && [ "$_cam_reply" != "yes" ]; then
        ux_info "Aborted"
        return 1
    fi

    # 1) 기존 symlink/bind mount 해제
    [ -L "$HOME/.claude/settings.json" ]                 && rm "$HOME/.claude/settings.json"
    [ -L "$HOME/.claude/statusline-command.sh" ]         && rm "$HOME/.claude/statusline-command.sh"
    [ -L "$HOME/.claude/projects/GLOBAL/memory" ]        && rm "$HOME/.claude/projects/GLOBAL/memory"
    if [ "${CLAUDE_SKIP_BIND_MOUNT:-0}" != "1" ]; then
        _is_mounted "$HOME/.claude/skills" && sudo umount "$HOME/.claude/skills"
        _is_mounted "$HOME/.claude/docs"   && sudo umount "$HOME/.claude/docs"
    fi

    # 2) 기존 plugins 실데이터를 공유 위치로 승격
    if [ -d "$HOME/.claude/plugins" ] && [ ! -L "$HOME/.claude/plugins" ]; then
        mkdir -p "$HOME/.claude-shared"
        if [ -d "$HOME/.claude-shared/plugins" ]; then
            ux_warning "  ~/.claude-shared/plugins already exists — keeping new, ignoring old"
        else
            mv "$HOME/.claude/plugins" "$HOME/.claude-shared/plugins"
        fi
    fi

    # 3) 디렉토리 자체 이동
    mv "$HOME/.claude" "$HOME/.claude-personal"

    # Diagnostic + safety net (issue #294): verify post-mv size matches and
    # seal a snapshot so claude_yolo can recover if .claude.json is later
    # reset (Claude CLI's first-run-with-new-CLAUDE_CONFIG_DIR can wipe it
    # to a `firstStartTime`-only stub, which kills oauthAccount/migration
    # cache and triggers a "configuration file not found" prompt).
    if [ -f "$HOME/.claude-personal/.claude.json" ]; then
        _cam_post_size=$(wc -c < "$HOME/.claude-personal/.claude.json" 2>/dev/null | tr -d ' ')
        ux_info "Post-migrate ~/.claude-personal/.claude.json size: ${_cam_post_size:-?} bytes"
        if [ -n "$_cam_pre_size" ] && [ -n "$_cam_post_size" ] \
           && [ "$_cam_pre_size" != "$_cam_post_size" ]; then
            ux_warning "  Size mismatch (pre=${_cam_pre_size}, post=${_cam_post_size}) —"
            ux_warning "  another process modified .claude.json during migrate."
        fi
        _cam_snap="$HOME/.claude-personal/.claude.json.preserved-by-migrate"
        if cp "$HOME/.claude-personal/.claude.json" "$_cam_snap" 2>/dev/null; then
            ux_info "Sealed snapshot: $_cam_snap"
            ux_info "  (claude-yolo auto-restores from this if .claude.json gets reset)"
        else
            ux_error "  Failed to create snapshot: $_cam_snap (recovery will be unavailable)"
        fi
    fi

    # 4) 빈 ~/.claude 재생성 + 모든 계정 init (멱등)
    claude_accounts_init

    ux_success "Migration complete. Personal data preserved at ~/.claude-personal/"
}

# claude_accounts_rollback — multi-account → single ~/.claude/ (issue #571).
#
# Reverse of `claude_accounts_migrate`. Promotes one account's directory
# back to ~/.claude/ and timestamp-backs-up the rest. Idempotent — when
# there are no ~/.claude-* dirs to roll back, it returns success without
# touching anything.
#
# Usage:
#   claude-accounts rollback             # auto-detect active account
#   claude-accounts rollback personal    # force-promote a specific account
#
# Auto-detect order:
#   1. The account whose .credentials.json exists (signals "logged in").
#   2. First existing ~/.claude-<name> dir among ENABLED_ACCOUNTS.
#
# Side effects:
#   - mv ~/.claude-<active>      → ~/.claude
#   - mv ~/.claude-<other>       → ~/.claude-<other>-rollback-<TS>-original
#   - mv ~/.claude (if non-empty)→ ~/.claude-pre-rollback-<TS>-original
#
# The Samsung internal PC use-case driving #571: a user ran
# `claude-accounts migrate` by mistake on an internal box (where the
# multi-account layout is structurally wrong), then `claude-yolo`
# hard-failed on the missing ~/.claude-personal check. Rollback gives
# them a one-shot recovery path without manual `mv`/`rm -rf`.
claude_accounts_rollback() {
    _car_active="${1:-}"

    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    # Auto-detect the active account when not passed explicitly.
    if [ -z "$_car_active" ]; then
        # First pass: prefer the account that's logged in.
        # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
        for _car_cand in ${CLAUDE_ENABLED_ACCOUNTS:-personal work}; do
            if [ -f "$HOME/.claude-${_car_cand}/.credentials.json" ]; then
                _car_active="$_car_cand"
                break
            fi
        done
        # Fallback: any existing ~/.claude-<name> dir.
        if [ -z "$_car_active" ]; then
            # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
            for _car_cand in ${CLAUDE_ENABLED_ACCOUNTS:-personal work}; do
                if [ -d "$HOME/.claude-${_car_cand}" ]; then
                    _car_active="$_car_cand"
                    break
                fi
            done
        fi
    fi

    ux_header "claude-accounts rollback — multi-account → single ~/.claude/"

    if [ -z "$_car_active" ]; then
        ux_info "No ~/.claude-* dirs to roll back — nothing to do (idempotent)"
        return 0
    fi

    _car_src="$HOME/.claude-${_car_active}"
    if [ ! -d "$_car_src" ]; then
        ux_error "Active account dir missing: $_car_src"
        ux_info  "Available: $(ls -d "$HOME"/.claude-* 2>/dev/null | tr '\n' ' ')"
        return 1
    fi

    ux_info "Active account:  $_car_active ($_car_src)"
    if [ "$(_dotfiles_setup_mode)" != "internal" ]; then
        # SC2088: the tilde here is a literal `~` in a user-facing path,
        # not a shell expansion — display form deliberately.
        # shellcheck disable=SC2088
        ux_warning "~/.dotfiles-setup-mode is not 'internal' — rollback is intended for"
        ux_warning "  the internal-PC single-account flow. Continuing anyway."
    fi

    _car_ts=$(date +%Y%m%d%H%M%S)

    # Step 1: Move out any existing ~/.claude/ contents.
    # Empty guard dirs (the kind setup.sh creates) → just rmdir, no backup.
    # Non-empty real dirs → timestamped backup (no auto-delete — user owns).
    # Symlinks → remove (they only point at SSOT, no data loss).
    if [ -L "$HOME/.claude" ]; then
        rm -f "$HOME/.claude"
        ux_info "  removed legacy ~/.claude symlink"
    elif [ -d "$HOME/.claude" ]; then
        if [ -z "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
            rmdir "$HOME/.claude" 2>/dev/null && \
                ux_info "  removed empty guard dir: ~/.claude"
        else
            _car_pre="$HOME/.claude-pre-rollback-${_car_ts}-original"
            mv "$HOME/.claude" "$_car_pre" || {
                ux_error "  backup failed: ~/.claude → $_car_pre — abort"
                return 1
            }
            ux_warning "  backed up existing ~/.claude → $_car_pre"
        fi
    fi

    # Step 2: Promote the active account's data to ~/.claude/.
    mv "$_car_src" "$HOME/.claude" || {
        ux_error "Move failed: $_car_src → ~/.claude"
        return 1
    }
    ux_success "  ~/.claude-${_car_active} → ~/.claude"

    # Step 3: Timestamp-backup every other ENABLED account that still has
    # a dir. Plugins are *not* moved — they live in ~/.claude-shared and
    # the active account already symlinks to that location.
    # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
    for _car_other in ${CLAUDE_ENABLED_ACCOUNTS:-personal work}; do
        [ "$_car_other" = "$_car_active" ] && continue
        _car_other_src="$HOME/.claude-${_car_other}"
        if [ -d "$_car_other_src" ]; then
            _car_other_bak="$HOME/.claude-${_car_other}-rollback-${_car_ts}-original"
            if mv "$_car_other_src" "$_car_other_bak"; then
                ux_info "  backed up: $_car_other_src → $_car_other_bak"
            else
                ux_warning "  backup failed for $_car_other_src — leaving in place"
            fi
        fi
    done

    ux_success "Rollback complete. ~/.claude/ is now the single config dir."
    ux_info "Next steps:"
    ux_info "  1. ./setup.sh   (re-select '2) Internal company PC' to wire single-account symlinks)"
    ux_info "  2. exec zsh     (reload shell)"
    ux_info "  3. claude-yolo  (no --user flag; multi-account dispatch is bypassed)"
}

_claude_accounts_help() {
    ux_header "claude-accounts — Claude Code multi-account management"
    ux_info "Usage: claude-accounts [<subcommand>]"
    ux_info ""
    ux_info "Subcommands:"
    ux_info "  status        (default) Show all accounts: path/credentials/symlinks/sync"
    ux_info "  list          List enabled accounts"
    ux_info "  setup         Idempotent setup (creates dirs + symlinks)"
    ux_info "  skills-sync   Re-sync skills/docs symlinks across all enabled accounts"
    ux_info "  migrate       One-time migration: ~/.claude → ~/.claude-personal (Home-PC)"
    ux_info "  rollback [<acct>]  Reverse of migrate: ~/.claude-<acct> → ~/.claude (issue #571)"
    ux_info "  -h|--help     This help"
    ux_info ""
    ux_info "Env vars:"
    ux_info "  CLAUDE_DEFAULT_ACCOUNT     Default for \`claude-yolo\` (default: personal)"
    ux_info "  CLAUDE_ENABLED_ACCOUNTS    Whitelist (default: 'personal work')"
    ux_info "  Override per-PC in shell-common/env/claude.local.sh"
}

claude_accounts() {
    case "${1:-status}" in
        status)         claude_accounts_status ;;
        list)           _claude_resolve_account --list ;;
        setup)          claude_accounts_init ;;
        skills-sync)    claude_skills_sync ;;
        migrate)        claude_accounts_migrate ;;
        rollback)       shift; claude_accounts_rollback "$@" ;;
        -h|--help|help) _claude_accounts_help ;;
        *)              ux_error "Unknown subcommand: $1"; _claude_accounts_help; return 1 ;;
    esac
}
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
