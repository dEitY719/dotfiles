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

# claude_yolo: run `claude --dangerously-skip-permissions`, but auto-switch
# off main/master to `scratch/MMDD-HHMMSS` first so YOLO sessions never
# land commits on the protected branch. Bypass with CLAUDE_YOLO_STAY=1.
claude_yolo() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        command claude --dangerously-skip-permissions "$@"
        return
    fi

    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    case "$branch" in
        main | master)
            if [ -z "${CLAUDE_YOLO_STAY:-}" ]; then
                new_branch="scratch/$(date +%m%d-%H%M%S)"
                ux_warning "main 브랜치 감지 → ${new_branch} 로 전환 (bypass: CLAUDE_YOLO_STAY=1)"
                git switch -c "$new_branch" || return 1
            fi
            ;;
    esac

    command claude --dangerously-skip-permissions "$@"
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

# claude_accounts_init — 멱등 setup, 3대 PC 공통 진입점.
claude_accounts_init() {
    ux_header "Claude Accounts Setup"

    # 마이그레이션 미수행 가드: 진짜 사용자 데이터(credentials, sessions,
    # projects, history)가 있을 때만 거부. 빈 skills/docs 디렉토리(기존
    # bind mount target 잔재)는 false positive 회피를 위해 무시.
    if [ -d "$HOME/.claude" ] \
       && [ ! -d "$HOME/.claude-personal" ] \
       && [ ! -d "$HOME/.claude-work" ] \
       && { [ -e "$HOME/.claude/.credentials.json" ] \
            || [ -d "$HOME/.claude/projects" ] \
            || [ -d "$HOME/.claude/sessions" ] \
            || [ -e "$HOME/.claude/history.jsonl" ] \
            || [ -d "$HOME/.claude/plugins" ]; }; then
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
