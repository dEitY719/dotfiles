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

# Initialize DOTFILES_BASH_DIR using common initialization function
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
source "$(dirname "$_SCRIPT_PATH")/util/init.bash"
DOTFILES_BASH_DIR="$(init_dotfiles_bash_dir "$_SCRIPT_PATH")"
export DOTFILES_BASH_DIR

# Set up SHELL_COMMON for unified UX library loading
SHELL_COMMON="${DOTFILES_BASH_DIR}/../shell-common"
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
log_debug() { echo "${UX_MUTED}[DEBUG] $1${UX_RESET}"; }
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

# Setup work_log.txt symlink (git-tracked, multi-PC sync)
# Points: ~/work_log.txt → dotfiles/shell-common/data/work_log.txt

WORK_LOG_SRC="${DOTFILES_BASH_DIR}/../shell-common/data/work_log.txt"
WORK_LOG_LINK="${HOME}/work_log.txt"

if [ -f "$WORK_LOG_SRC" ]; then
    # Ensure symlink exists
    if [ -L "$WORK_LOG_LINK" ]; then
        # Already a symlink, verify it points to correct location
        current_target=$(readlink "$WORK_LOG_LINK")
        if [ "$current_target" != "$WORK_LOG_SRC" ]; then
            log_error "경고: ~/.work_log.txt는 다른 위치를 가리키고 있습니다"
            log_dim "기존: $current_target"
            log_dim "새로: $WORK_LOG_SRC"
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
        # File doesn't exist, create symlink
        create_symlink "$WORK_LOG_SRC" "$WORK_LOG_LINK"
    fi
else
    log_error "경고: work_log.txt 소스를 찾을 수 없습니다: $WORK_LOG_SRC"
fi

log_debug "--- dotfiles setup 완료 ---"

log_dim "변경 사항을 적용하려면 'source ~/.bashrc' 또는 셸을 재시작하십시오."

log_dim "만약 ~/.bash_profile도 새로 링크했다면 'source ~/.bash_profile' 하거나 로그인 셸을 재시작하십시오."

exit 0
