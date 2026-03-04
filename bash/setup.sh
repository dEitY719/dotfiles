#!/bin/bash

# bash/setup.sh: Bash shell environment setup
#
# PURPOSE: Set up bash shell with special initialization
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL INITIALIZATION (why this file is REQUIRED):
#   1. Sets DOTFILES_BASH_DIR environment variable (needed by bash/main.bash)
#   2. Sets SHELL_COMMON environment variable (needed by all bash functions)
#   3. Creates ~/.bashrc symlink
#   4. Creates ~/.bash_profile symlink (optional)
#
# These environment variables are NOT set by install.sh and are CRITICAL
# for bash shell initialization to work properly.
#
# See SETUP_GUIDE.md for more information

# --- Constants ---

# Initialize DOTFILES_BASH_DIR using unified path resolution
# NOTE: Use realpath to follow symlinks
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
_SCRIPT_DIR="$(dirname "$_SCRIPT_PATH")"
DOTFILES_BASH_DIR="$_SCRIPT_DIR"
export DOTFILES_BASH_DIR

# Set up SHELL_COMMON for unified UX library loading
DOTFILES_ROOT="${DOTFILES_BASH_DIR%/bash}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
export SHELL_COMMON

MAIN_BASH_SOURCE="${DOTFILES_BASH_DIR}/main.bash"

HOME_BASHRC="${HOME}/.bashrc"

HOME_BASH_PROFILE="${HOME}/.bash_profile"

# --- Logging Initialization ---

# init_logging 함수를 호출하여 로깅 기능을 초기화합니다.
# DOTFILES_BASH_DIR 변수를 인자로 전달합니다.

# Load UX library (unified library at shell-common/tools/ux_lib/)
source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

# Define legacy mapping functions for backward compatibility
log_info() { ux_info "$1"; }
log_error() { ux_error "$1"; }
log_critical() {
    ux_error "$1"
    exit 1
}
log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }
log_debug() { echo -e "${UX_MUTED}[DEBUG] $1${UX_RESET}"; }
log_warning() { ux_warning "$1"; }

# --- Functions ---

# log_critical 함수를 사용하여 log_error_and_exit 대체

log_error_and_exit() {

    log_critical "$1" # log_critical 함수를 호출하여 에러 메시지 출력 후 종료

}

backup_file() {
    local file_to_backup="$1"
    local backup_destination="$2"
    if [ -e "$file_to_backup" ]; then
        log_info "백업 파일 생성: $file_to_backup -> $backup_destination"
        cp "$file_to_backup" "$backup_destination" || log_error_and_exit "백업 파일 생성 실패: $file_to_backup"
    fi
}

create_symlink() {

    local target="$1"

    local link_name="$2"

    if [ -L "$link_name" ]; then

        log_dim "기존 심볼릭 링크 제거: $link_name"

        rm "$link_name" || log_error_and_exit "기존 심볼릭 링크 제거 실패: $link_name"

    elif [ -f "$link_name" ]; then

        log_warning "경고: $link_name 가 심볼릭 링크가 아닌 일반 파일입니다. 백업 후 제거합니다."

        backup_file "$link_name" "${link_name}-$(date +%Y%m%d%H%M%S)-original"

        rm "$link_name" || log_error_and_exit "기존 파일 제거 실패: $link_name"

    fi

    log_info "심볼릭 링크 생성: $link_name -> $target"

    ln -s "$target" "$link_name" || log_error_and_exit "심볼릭 링크 생성 실패: $link_name -> $target"

}

# --- Main Script Logic ---

log_debug "\n--- dotfiles setup 시작 ---"

# main.bash 파일 존재 여부 확인

if [ ! -f "$MAIN_BASH_SOURCE" ]; then

    log_error_and_exit "main.bash 파일이 '${MAIN_BASH_SOURCE}' 경로에 존재하지 않습니다. 파일을 먼저 생성해주세요."

fi

# ~/.bashrc 로 심볼릭링크

create_symlink "$MAIN_BASH_SOURCE" "$HOME_BASHRC"

# ~/.bash_profile도 심볼릭링크 (선택 사항)

if [ -f "${DOTFILES_BASH_DIR}/profile.bash" ]; then

    log_dim "profile.bash 파일이 존재하므로 ~/.bash_profile 심볼릭 링크를 생성합니다."

    create_symlink "${DOTFILES_BASH_DIR}/profile.bash" "$HOME_BASH_PROFILE"

else

    log_error "경고: ${DOTFILES_BASH_DIR}/profile.bash 파일이 없습니다. ~/.bash_profile 심볼릭 링크를 생성하지 않습니다."

fi

# Setup work_log.txt symlink (multi-PC sync)
# Points: ~/work_log.txt → para/archive/playbook/logs/work_log.txt
# Note: Managed via playbook/logs, not dotfiles

WORK_LOG_SRC="${HOME}/para/archive/playbook/logs/work_log.txt"
WORK_LOG_LINK="${HOME}/work_log.txt"

# Only setup if source file exists
if [ -f "$WORK_LOG_SRC" ]; then
    if [ -L "$WORK_LOG_LINK" ]; then
        # Already a symlink, verify it points to correct location
        current_target=$(readlink -f "$WORK_LOG_LINK")
        expected_target=$(readlink -f "$WORK_LOG_SRC")
        if [ "$current_target" != "$expected_target" ]; then
            log_error "경고: ~/.work_log.txt는 다른 위치를 가리키고 있습니다"
            log_dim "기존: $current_target"
            log_dim "새로: $expected_target"
        else
            log_debug "✓ work_log.txt 심볼릭 링크 확인됨"
        fi
    elif [ -f "$WORK_LOG_LINK" ]; then
        # Regular file exists, backup and create symlink
        backup_file="${WORK_LOG_LINK}.backup.$(date +%s)"
        log_error "경고: ~/work_log.txt가 일반 파일입니다"
        log_dim "백업: $backup_file로 이동"
        mv "$WORK_LOG_LINK" "$backup_file"
        create_symlink "$WORK_LOG_SRC" "$WORK_LOG_LINK"
    else
        # Symlink doesn't exist, create it
        create_symlink "$WORK_LOG_SRC" "$WORK_LOG_LINK"
    fi
fi

# Cleanup: Remove broken plugin references from ~/.zshrc
# Prevents "plugin not found" errors when zsh starts
_cleanup_broken_zsh_plugins() {
    local zshrc="${HOME}/.zshrc"
    local omz_custom="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"

    if [ ! -f "$zshrc" ]; then
        return 0
    fi

    # Check for plugins that are registered but not installed
    local broken_plugins=""

    # Common plugins to check
    local plugins_to_check="zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search"

    for plugin in $plugins_to_check; do
        # If plugin is registered in zshrc but not installed, mark for removal
        if grep -q "$plugin" "$zshrc" && [ ! -d "$omz_custom/plugins/$plugin" ]; then
            broken_plugins="$broken_plugins $plugin"
        fi
    done

    if [ -z "$broken_plugins" ]; then
        return 0
    fi

    # Create backup
    local backup_file
    backup_file="${zshrc}.backup.$(date +%s)"
    cp "$zshrc" "$backup_file" || return 1

    log_debug "정리: ~/.zshrc에서 설치되지 않은 플러그인 제거: $broken_plugins"

    # Remove each broken plugin
    local temp_zshrc="${zshrc}.tmp"
    cp "$zshrc" "$temp_zshrc"

    for plugin in $broken_plugins; do
        # Remove plugin from plugins array
        # Handles: "plugin" " plugin" "plugin " and variations
        sed -i.bak "s/ $plugin//g; s/$plugin //g; s/$plugin$//g" "$temp_zshrc" 2>/dev/null || true
    done

    # Verify the file is valid before replacing
    if grep -q "plugins=(" "$temp_zshrc" 2>/dev/null; then
        mv "$temp_zshrc" "$zshrc"
        rm -f "${zshrc}.bak" 2>/dev/null
        log_dim "✓ ~/.zshrc에서 미설치 플러그인 제거 완료"
        log_dim "  이제 zsh 시작 시 'plugin not found' 에러가 나타나지 않습니다"
    else
        # Restore backup if something went wrong
        mv "$backup_file" "$zshrc"
        log_error "경고: ~/.zshrc 정리 중 오류 발생, 백업에서 복구됨"
        return 1
    fi
}

# Run cleanup if zshrc exists
_cleanup_broken_zsh_plugins

# Add auto-cleanup code to ~/.zshrc (if not already there)
_add_zshrc_auto_cleanup() {
    local zshrc="${HOME}/.zshrc"
    local marker="# DOTFILES AUTO-CLEANUP: Remove broken plugin references"

    if [ ! -f "$zshrc" ]; then
        return 0
    fi

    # Check if auto-cleanup code is already added
    if grep -q "$marker" "$zshrc" 2>/dev/null; then
        return 0
    fi

    # Add auto-cleanup code at the beginning of ~/.zshrc
    # This runs every time zsh starts to ensure no broken plugins
    if cat >"${zshrc}.cleanup_insert" <<'CLEANUP_CODE'

# ═══════════════════════════════════════════════════════════════
# DOTFILES AUTO-CLEANUP: Remove broken plugin references
# ═══════════════════════════════════════════════════════════════
# This code runs automatically when zsh starts to ensure no
# "plugin not found" errors occur. Plugins are only loaded if
# they are actually installed in ~/.oh-my-zsh/custom/plugins/

_dotfiles_auto_cleanup_plugins() {
    local omz_custom="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
    local modified=0

    # Check for broken plugin references in plugins array
    for plugin_name in zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search; do
        if [[ "$plugins" == *"$plugin_name"* ]] && [ ! -d "$omz_custom/plugins/$plugin_name" ]; then
            # Remove broken plugin reference
            plugins=("${(@)plugins[@]//$plugin_name}")
            modified=1
        fi
    done
}

_dotfiles_auto_cleanup_plugins
unfunction _dotfiles_auto_cleanup_plugins 2>/dev/null || true

CLEANUP_CODE

    then
        # Prepend cleanup code to zshrc
        cat "${zshrc}.cleanup_insert" "$zshrc" >"${zshrc}.new"
        mv "${zshrc}.new" "$zshrc"
        rm -f "${zshrc}.cleanup_insert"
        log_debug "✓ ~/.zshrc에 자동 정리 코드 추가됨 (매번 zsh 시작 시 자동 실행)"
    fi
}

# Add auto-cleanup to zshrc
_add_zshrc_auto_cleanup

log_debug "--- dotfiles setup 완료 ---"

log_dim "변경 사항을 적용하려면 'source ~/.bashrc' 또는 셸을 재시작하십시오."

log_dim "만약 ~/.bash_profile도 새로 링크했다면 'source ~/.bash_profile' 하거나 로그인 셸을 재시작하십시오."

exit 0
