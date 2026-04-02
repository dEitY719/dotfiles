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

_codex_home_dir() {
    local xdg_codex_home

    if [ -n "${CODEX_HOME:-}" ]; then
        echo "$CODEX_HOME"
        return 0
    fi

    if [ -d "$HOME/.codex" ]; then
        echo "$HOME/.codex"
        return 0
    fi

    xdg_codex_home="${XDG_CONFIG_HOME:-$HOME/.config}/codex"
    if [ -d "$xdg_codex_home" ]; then
        echo "$xdg_codex_home"
        return 0
    fi

    if [ -d "$HOME/.cod" ]; then
        echo "$HOME/.cod"
        return 0
    fi

    echo "$HOME/.codex"
}

_codex_skills_target_dir() {
    echo "$(_codex_home_dir)/skills"
}

_codex_skills_state_file() {
    echo "$(_codex_home_dir)/.skills-sync-state"
}

_codex_skills_state_version() {
    echo "2"
}

_codex_skills_fingerprint() {
    local src="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"
    local skill_path skill_file

    [ -d "$src" ] || return 1

    (
        cd "$src" || exit 1
        find . -mindepth 1 -maxdepth 2 -not -name "." -not -name ".." | LC_ALL=C sort | while IFS= read -r skill_path; do
            printf "entry:%s\n" "$skill_path"
        done
        find . -mindepth 2 -maxdepth 2 -name "SKILL.md" | LC_ALL=C sort | while IFS= read -r skill_path; do
            skill_file="$src/${skill_path#./}"
            [ -f "$skill_file" ] || continue
            printf "skill-md:%s:%s\n" "$skill_path" "$(cksum < "$skill_file" | awk '{print $1 ":" $2}')"
        done
    ) | LC_ALL=C sort | cksum | awk '{print $1 ":" $2}'
}

_codex_skills_state_signature() {
    local sync_script skills_fingerprint script_fingerprint codex_home

    skills_fingerprint="$(_codex_skills_fingerprint 2>/dev/null)" || return 1
    sync_script="$(_codex_skills_sync_script)"
    codex_home="$(_codex_home_dir)"
    codex_home="$(readlink -f "$codex_home" 2>/dev/null || printf "%s" "$codex_home")"

    if [ -f "$sync_script" ]; then
        script_fingerprint="$(cksum < "$sync_script" | awk '{print $1 ":" $2}')"
    else
        script_fingerprint="missing"
    fi

    printf "%s|%s|%s|%s\n" "$(_codex_skills_state_version)" "$skills_fingerprint" "$script_fingerprint" "$codex_home"
}

_codex_skills_write_state() {
    local signature="$1"
    local state_file
    state_file="$(_codex_skills_state_file)"
    mkdir -p "$(dirname "$state_file")" >/dev/null 2>&1 || true
    printf "%s\n" "$signature" > "$state_file"
}

_codex_skills_read_state() {
    local state_file
    state_file="$(_codex_skills_state_file)"
    [ -f "$state_file" ] || return 1
    head -n 1 "$state_file"
}

_codex_skills_has_legacy_symlinked_skill_md() {
    local target_dir
    local legacy_link

    target_dir="$(_codex_skills_target_dir)"
    [ -d "$target_dir" ] || return 1

    legacy_link="$(find "$target_dir" -mindepth 2 -maxdepth 2 -type l -name "SKILL.md" -print -quit 2>/dev/null)"
    [ -n "$legacy_link" ]
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
    local current_signature previous_signature sync_reason

    current_signature="$(_codex_skills_state_signature 2>/dev/null)" || return 0
    previous_signature="$(_codex_skills_read_state 2>/dev/null || true)"
    sync_reason="changes"

    if [ "$force" -eq 0 ] && [ "$current_signature" = "$previous_signature" ]; then
        if _codex_skills_has_legacy_symlinked_skill_md; then
            sync_reason="legacy-layout"
        else
            return 0
        fi
    fi

    if [ "$quiet" -eq 0 ]; then
        if [ "$sync_reason" = "legacy-layout" ]; then
            ux_info "Legacy codex skill layout detected. Syncing codex skills..."
        else
            ux_info "Skill changes detected. Syncing codex skills..."
        fi
    fi

    if _codex_skills_run_sync_script "$quiet"; then
        _codex_skills_write_state "$current_signature"
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

_codex_auto_sync_interval_seconds() {
    local interval
    interval="${CODEX_SKILLS_AUTO_SYNC_INTERVAL:-5}"
    case "$interval" in
        ''|*[!0-9]*)
            interval=5
            ;;
    esac
    echo "$interval"
}

_codex_should_run_periodic_sync() {
    local now last interval
    interval="$(_codex_auto_sync_interval_seconds)"
    now="$(date +%s 2>/dev/null || echo 0)"
    last="${CODEX_SKILLS_AUTO_SYNC_LAST_CHECK:-0}"

    if [ "$((now - last))" -lt "$interval" ]; then
        return 1
    fi

    CODEX_SKILLS_AUTO_SYNC_LAST_CHECK="$now"
    return 0
}

_codex_periodic_auto_sync() {
    if ! _codex_auto_sync_enabled; then
        return 0
    fi

    if ! _codex_should_run_periodic_sync; then
        return 0
    fi

    if _codex_auto_sync_quiet; then
        codex_skills_sync_if_needed 1 0
    else
        codex_skills_sync_if_needed 0 0
    fi
}

_codex_register_auto_sync_hooks() {
    # Only interactive shells should register prompt hooks.
    case "$-" in
        *i*) ;;
        *) return 0 ;;
    esac

    if [ "${CODEX_AUTO_SYNC_HOOKS_REGISTERED:-0}" = "1" ]; then
        return 0
    fi
    CODEX_AUTO_SYNC_HOOKS_REGISTERED=1

    if [ -n "${BASH_VERSION:-}" ]; then
        case ";${PROMPT_COMMAND:-};" in
            *";_codex_periodic_auto_sync;"*)
                ;;
            *)
                if [ -n "${PROMPT_COMMAND:-}" ]; then
                    PROMPT_COMMAND="_codex_periodic_auto_sync; ${PROMPT_COMMAND}"
                else
                    PROMPT_COMMAND="_codex_periodic_auto_sync"
                fi
                ;;
        esac
        return 0
    fi

    if [ -n "${ZSH_VERSION:-}" ]; then
        autoload -Uz add-zsh-hook >/dev/null 2>&1 || return 0
        add-zsh-hook precmd _codex_periodic_auto_sync >/dev/null 2>&1 || true
    fi
}

_codex_maybe_auto_sync() {
    local prev_in_progress
    prev_in_progress="${CODEX_AUTO_SYNC_IN_PROGRESS:-0}"
    if [ "$prev_in_progress" = "1" ]; then
        return 0
    fi
    CODEX_AUTO_SYNC_IN_PROGRESS=1

    if ! _codex_auto_sync_enabled; then
        CODEX_AUTO_SYNC_IN_PROGRESS="$prev_in_progress"
        return 0
    fi

    if _codex_auto_sync_quiet; then
        codex_skills_sync_if_needed 1 0
    else
        codex_skills_sync_if_needed 0 0
    fi

    CODEX_AUTO_SYNC_IN_PROGRESS="$prev_in_progress"
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

# Prime state once per interactive shell session.
_codex_maybe_auto_sync
_codex_register_auto_sync_hooks
