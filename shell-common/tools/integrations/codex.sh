#!/bin/sh
# shell-common/tools/codex.sh
# Codex CLI - utilities and workflow helpers
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Installation & Setup Guide
# ═══════════════════════════════════════════════════════════════

# 1) npm 전역 설치
#    npm config set prefix '~/.npm-global'
#    bash shell-common/tools/custom/install_codex.sh
#    또는 수동 설치:
#    npm install -g <codex-package-name>
#
# 2) API 키 또는 웹 로그인 인증
#    설정 파일 또는 환경 변수로 인증 필요
#    ~/.env 파일에 저장하거나, codex 명령어로 직접 인증

# ═══════════════════════════════════════════════════════════════
# Essential Command Aliases
# ═══════════════════════════════════════════════════════════════

alias codex-help='codex --help'     # Show help
alias codex-version='codex --version' # Show version
alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'
alias codex-skills-sync='codex_skills_sync' # Sync skills symlinks
alias codex-install='codex_install' # Install Codex CLI
alias codex-uninstall='codex_uninstall' # Uninstall Codex CLI
alias codex-status='codex_status'   # Check Codex status

# ═══════════════════════════════════════════════════════════════
# Codex Skills Sync
# ═══════════════════════════════════════════════════════════════

_codex_skills_sync_script() {
    echo "${DOTFILES_ROOT:-$HOME/dotfiles}/scripts/setup-skills-ssot.sh"
}

_codex_skills_state_file() {
    echo "$HOME/.codex/.skills-sync-state"
}

_codex_skills_fingerprint() {
    local src="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"
    local skill_dir entry entry_name

    [ -d "$src" ] || return 1

    # zsh: prevent nomatch errors for patterns like "$skill_dir".*
    if [ -n "$ZSH_VERSION" ]; then
        setopt local_options nonomatch
    fi

    (
        for skill_dir in "$src"/*/; do
            [ -d "$skill_dir" ] || continue
            echo "skill:$(basename "$skill_dir")"
            for entry in "$skill_dir"* "$skill_dir".*; do
                [ -e "$entry" ] || continue
                entry_name=$(basename "$entry")
                if [ "$entry_name" = "." ] || [ "$entry_name" = ".." ]; then
                    continue
                fi
                echo "entry:$(basename "$skill_dir")/$entry_name"
            done
        done
    ) | LC_ALL=C sort | cksum | awk '{print $1 ":" $2}'
}

_codex_skills_write_state() {
    local fingerprint="$1"
    local state_file
    state_file="$(_codex_skills_state_file)"
    mkdir -p "$(dirname "$state_file")" >/dev/null 2>&1 || true
    printf "%s\n" "$fingerprint" > "$state_file"
}

_codex_skills_read_state() {
    local state_file
    state_file="$(_codex_skills_state_file)"
    [ -f "$state_file" ] || return 1
    head -n 1 "$state_file"
}

_codex_skills_run_sync_script() {
    local quiet="${1:-0}"
    local sync_script
    sync_script="$(_codex_skills_sync_script)"

    if [ ! -f "$sync_script" ]; then
        [ "$quiet" -eq 1 ] || ux_error "Sync script not found: $sync_script"
        return 1
    fi

    if [ "$quiet" -eq 1 ]; then
        bash "$sync_script" >/dev/null 2>&1
    else
        bash "$sync_script"
    fi
}

codex_skills_sync_if_needed() {
    local quiet="${1:-0}"
    local force="${2:-0}"
    local current_fingerprint previous_fingerprint

    current_fingerprint="$(_codex_skills_fingerprint 2>/dev/null)" || return 0
    previous_fingerprint="$(_codex_skills_read_state 2>/dev/null || true)"

    if [ "$force" -eq 0 ] && [ "$current_fingerprint" = "$previous_fingerprint" ]; then
        return 0
    fi

    if [ "$quiet" -eq 0 ]; then
        ux_info "Skill changes detected. Syncing codex skills..."
    fi

    if _codex_skills_run_sync_script "$quiet"; then
        _codex_skills_write_state "$current_fingerprint"
        [ "$quiet" -eq 1 ] || ux_success "Codex skills sync completed"
        return 0
    fi

    [ "$quiet" -eq 1 ] || ux_error "Codex skills sync failed"
    return 1
}

codex_skills_sync() {
    ux_header "Codex Skills Sync"
    codex_skills_sync_if_needed 0 1
}

_codex_auto_sync_enabled() {
    [ "${CODEX_SKILLS_AUTO_SYNC:-1}" != "0" ]
}

_codex_auto_sync_quiet() {
    [ "${CODEX_SKILLS_AUTO_SYNC_VERBOSE:-0}" != "1" ]
}

_codex_maybe_auto_sync() {
    if ! _codex_auto_sync_enabled; then
        return 0
    fi

    if _codex_auto_sync_quiet; then
        codex_skills_sync_if_needed 1 0
    else
        codex_skills_sync_if_needed 0 0
    fi
}

codex() {
    _codex_maybe_auto_sync
    command codex "$@"
}

# ═══════════════════════════════════════════════════════════════
# Codex Installation
# ═══════════════════════════════════════════════════════════════

codex_install() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_codex.sh"
}

# ═══════════════════════════════════════════════════════════════
# Codex Uninstallation
# ═══════════════════════════════════════════════════════════════

codex_uninstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/uninstall_codex.sh"
}

# ═══════════════════════════════════════════════════════════════
# Codex Status Check
# ═══════════════════════════════════════════════════════════════

codex_status() {
    ux_header "Codex Status"

    if command -v codex > /dev/null 2>&1; then
        ux_success "Codex installed"
        ux_table_row "Version" "$(codex --version 2>/dev/null || echo 'unknown')" ""
        ux_table_row "Location" "$(which codex)" ""
    else
        ux_warning "Codex not found"
        ux_info "To install: bash shell-common/tools/custom/install_codex.sh"
        return 1
    fi

    echo ""
    ux_section "npm Global Packages"
    if ! npm list -g --depth=0 | grep -i codex > /dev/null 2>&1; then
        echo "  (No codex packages found)"
    fi
}

# Prime skills state once per interactive shell session.
_codex_maybe_auto_sync
