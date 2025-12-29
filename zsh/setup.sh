#!/bin/bash

# zsh/setup.sh
# Zsh setup script for dotfiles initialization

# --- Constants ---

# Initialize DOTFILES_ROOT and other paths
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZSH_DOTFILES="${DOTFILES_ROOT}/zsh"
MAIN_ZSH_SOURCE="${ZSH_DOTFILES}/main.zsh"
HOME_ZSHRC="${HOME}/.zshrc"

# Load UX library from bash for setup feedback
BASH_UX_LIB="${DOTFILES_ROOT}/bash/ux_lib/ux_lib.bash"
if [ -f "$BASH_UX_LIB" ]; then
    source "$BASH_UX_LIB"
else
    echo "Error: UX library not found at $BASH_UX_LIB"
    exit 1
fi

# --- Logging Compatibility Functions ---

# Legacy logging functions for consistency with bash/setup.sh
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

log_error_and_exit() {
    log_critical "$1"
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

log_debug "\n--- zsh dotfiles setup 시작 ---"

# main.zsh 파일 존재 여부 확인
if [ ! -f "$MAIN_ZSH_SOURCE" ]; then
    log_error_and_exit "main.zsh 파일이 '${MAIN_ZSH_SOURCE}' 경로에 존재하지 않습니다. 파일을 먼저 생성해주세요."
fi

# ~/.zshrc 를 심볼릭 링크로 생성
create_symlink "$MAIN_ZSH_SOURCE" "$HOME_ZSHRC"

# --- Completion Messages ---

log_debug "--- zsh dotfiles setup 완료 ---"
echo ""

ux_success "Zsh 설정이 완료되었습니다!"
ux_info "변경 사항을 적용하려면 다음 중 하나를 실행하세요:"
ux_bullet "현재 셸 리로드: ${UX_BOLD}exec zsh${UX_RESET}"
ux_bullet "또는 새 터미널 창을 여세요"
echo ""

ux_section "다음 단계"
ux_bullet "Zsh 관리 명령어: ${UX_BOLD}zsh-help${UX_RESET}"
ux_bullet "테마 변경: ${UX_BOLD}zsh-themes${UX_RESET}, ${UX_BOLD}zsh-theme <name>${UX_RESET}"
ux_bullet "플러그인 확인: ${UX_BOLD}zsh-plugins${UX_RESET}"
echo ""

exit 0
