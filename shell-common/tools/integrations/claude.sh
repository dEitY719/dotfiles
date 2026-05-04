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

    # zsh disables word-splitting; emulate sh inside this function.
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    # --user 가로채고 나머지는 위치 인자로 보존 (POSIX 안전)
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

    # 계정 → CONFIG_DIR (SSOT 호출)
    _cy_config_dir=$(_claude_resolve_account "$_cy_account") || {
        ux_error "Unknown account: $_cy_account"
        ux_info  "Available: $(_claude_resolve_account --list | tr '\n' ' ')"
        return 1
    }

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

    CLAUDE_CONFIG_DIR="$_cy_config_dir" command claude --dangerously-skip-permissions "$@"
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

    [ -f "$_crir_live" ] || return 0
    [ -f "$_crir_snap" ] || return 0

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

# _claude_resolve_account — 계정 매핑 SSOT (case dispatcher).
# Usage:
#   _claude_resolve_account <name>     → echo CONFIG_DIR (exit 0) or fail (exit 1)
#   _claude_resolve_account --list     → echo enabled accounts (one per line)
#   _claude_resolve_account --list-all → echo all defined accounts (debug)
#
# 새 계정 추가 시 case 한 줄 + --list-all 한 단어만 추가.
_claude_resolve_account() {
    # zsh disables word-splitting by default; emulate sh inside this function
    # so `for x in $LIST` behaves identically to bash/dash. (See MEMORY.md
    # "Zsh-Specific Tracing Behavior" for the same pattern in gcp_scan.sh.)
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    case "$1" in
        --list)
            # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
            for _cra_acct in $CLAUDE_ENABLED_ACCOUNTS; do
                _claude_resolve_account "$_cra_acct" >/dev/null 2>&1 && echo "$_cra_acct"
            done
            ;;
        --list-all)
            echo "personal work"
            ;;
        personal) echo "$HOME/.claude-personal" ;;
        work)     echo "$HOME/.claude-work" ;;
        *)        return 1 ;;
    esac
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

# _claude_account_setup_one — 단일 계정의 link/mount 멱등 셋업.
_claude_account_setup_one() {
    _caso_acct="$1"
    _caso_cdir="$2"
    ux_section "Account: $_caso_acct ($_caso_cdir)"

    mkdir -p "$_caso_cdir"
    mkdir -p "$_caso_cdir/projects/GLOBAL"

    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/settings.json"          "$_caso_cdir/settings.json"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/statusline-command.sh"  "$_caso_cdir/statusline-command.sh"
    _claude_ensure_symlink "$HOME/.claude-shared/plugins"                   "$_caso_cdir/plugins"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/global-memory"          "$_caso_cdir/projects/GLOBAL/memory"

    if [ "${CLAUDE_SKIP_BIND_MOUNT:-0}" = "1" ]; then
        # Visible warning, not info — production users may misuse this and
        # silently lose bind mounts. Test harness sees the warning too.
        ux_warning "  (CLAUDE_SKIP_BIND_MOUNT=1 → skipping bind mounts)"
    else
        _claude_ensure_bind_mount "${DOTFILES_ROOT}/claude/skills"  "$_caso_cdir/skills"
        _claude_ensure_bind_mount "${DOTFILES_ROOT}/claude/docs"    "$_caso_cdir/docs"
    fi
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

        for _cas_link in settings.json statusline-command.sh plugins projects/GLOBAL/memory; do
            if [ -L "$_cas_cdir/$_cas_link" ]; then
                echo "  $_cas_link: symlink ✓"
            else
                echo "  $_cas_link: ✗ missing"
            fi
        done

        for _cas_mount in skills docs; do
            if _is_mounted "$_cas_cdir/$_cas_mount"; then
                echo "  $_cas_mount: bind mount ✓"
            else
                echo "  $_cas_mount: ✗ not mounted"
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
_claude_has_unmigrated_data() {
    [ -d "$HOME/.claude" ] || return 1
    [ -d "$HOME/.claude-personal" ] && return 1
    [ -d "$HOME/.claude-work" ] && return 1
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

_claude_accounts_help() {
    ux_header "claude-accounts — Claude Code multi-account management"
    ux_info "Usage: claude-accounts [<subcommand>]"
    ux_info ""
    ux_info "Subcommands:"
    ux_info "  status     (default) Show all accounts: path/credentials/symlinks/mounts"
    ux_info "  list       List enabled accounts"
    ux_info "  setup      Idempotent setup (creates dirs, symlinks, bind mounts)"
    ux_info "  migrate    One-time migration: ~/.claude → ~/.claude-personal (Home-PC)"
    ux_info "  -h|--help  This help"
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
        migrate)        claude_accounts_migrate ;;
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
