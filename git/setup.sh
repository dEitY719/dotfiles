#!/bin/bash

# ~/dotfiles/git/setup.sh
# setup.sh for Git dotfiles


# --- Constants ---
# 현재 스크립트가 위치한 git 디렉토리의 절대 경로를 설정합니다.
DOTFILES_GIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# gitdotfiles의 특정 파일들
GIT_CONFIG_SOURCE="${DOTFILES_GIT_DIR}/.gitconfig"


# 홈 디렉토리에 생성될 심볼릭 링크의 대상 경로
HOME_GITCONFIG="${HOME}/.gitconfig"


# --- Logging Initialization ---
# ux_lib.bash를 로드합니다.
# setup.sh가 dotfiles/git에 있으므로, dotfiles/bash/ux_lib는 ../bash/ux_lib에 있습니다.
UX_LIB_SCRIPT="${DOTFILES_GIT_DIR}/../bash/ux_lib/ux_lib.bash"


if [[ -f "${UX_LIB_SCRIPT}" ]]; then
    source "${UX_LIB_SCRIPT}"
else
    echo "CRITICAL ERROR: UX library script not found at ${UX_LIB_SCRIPT}. Exiting." >&2
    exit 1
fi


# --- Functions ---
# log_critical 함수를 사용하여 log_error_and_exit 대체
log_error_and_exit() {
    ux_error "$1"
    exit 1
}


backup_file() {
    local file_to_backup="$1"
    local backup_destination="$2"
    if [ -e "$file_to_backup" ]; then
        ux_info "백업 파일 생성: $file_to_backup -> $backup_destination"
        cp "$file_to_backup" "$backup_destination" || log_error_and_exit "백업 파일 생성 실패: $file_to_backup"
    fi
}


create_symlink() {
    local target="$1"
    local link_name="$2"

    if [ -L "$link_name" ]; then
        # ux_dim does not exist, use muted style or echo with UX_MUTED
        echo "${UX_MUTED}기존 심볼릭 링크 제거: $link_name${UX_RESET}"
        rm "$link_name" || log_error_and_exit "기존 심볼릭 링크 제거 실패: $link_name"
    elif [ -f "$link_name" ]; then
        ux_warning "경고: $link_name 가 심볼릭 링크가 아닌 일반 파일입니다. 백업 후 제거합니다."
        backup_file "$link_name" "${link_name}-$(date +%Y%m%d%H%M%S)-original"
        rm "$link_name" || log_error_and_exit "기존 파일 제거 실패: $link_name"
    fi

    echo "${UX_MUTED}심볼릭 링크 생성: $link_name -> $target${UX_RESET}"
    ln -s "$target" "$link_name" || log_error_and_exit "심볼릭 링크 생성 실패: $link_name -> $target"
}


# --- Main Script Logic ---
ux_header "Git dotfiles setup 시작"


# .gitconfig 심볼릭 링크 생성
if [ -f "$GIT_CONFIG_SOURCE" ]; then
    create_symlink "$GIT_CONFIG_SOURCE" "$HOME_GITCONFIG"
else
    ux_warning "경고: .gitconfig 파일이 '${GIT_CONFIG_SOURCE}' 경로에 없습니다. 심볼릭 링크를 생성하지 않습니다."
fi


ux_success "Git dotfiles setup 완료"
echo "${UX_MUTED}Git 설정이 적용되었습니다.${UX_RESET}"

exit 0