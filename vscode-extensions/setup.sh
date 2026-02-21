#!/bin/bash

# vscode-extensions/setup.sh: VS Code extensions configuration setup
#
# PURPOSE: Set up VS Code extensions configuration with symbolic links
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL INITIALIZATION (why this file is REQUIRED):
#   1. Creates ~/.prettierrc symlink (Prettier formatter configuration)
#   2. Provides user feedback using UX library
#   3. Ensures proper VS Code formatter initialization across all projects
#
# These files are version-controlled in dotfiles and should be managed
# via symbolic links for consistency across machines.
#
# See SETUP_GUIDE.md for more information

# --- Constants ---

# Initialize DOTFILES_ROOT
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"
VSCODE_EXTENSIONS_DOTFILES="${DOTFILES_ROOT}/vscode-extensions"

# Home directory locations
HOME_PRETTIERRC="${HOME}/.prettierrc"

# Dotfiles source locations
PRETTIERRC_SOURCE="${VSCODE_EXTENSIONS_DOTFILES}/.prettierrc"

# Load UX library (unified library at shell-common/tools/ux_lib/)
UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    source "$UX_LIB"
else
    echo "Error: UX library not found at $UX_LIB"
    exit 1
fi

# --- Logging Compatibility Functions ---

log_info() { ux_info "$1"; }
log_error() { ux_error "$1"; }
log_critical() {
    ux_error "$1"
    exit 1
}
log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }
log_debug() { echo "${UX_MUTED}[DEBUG] $1${UX_RESET}"; }
log_warning() { ux_warning "$1"; }

log_error_and_exit() {
    log_critical "$1"
}

# --- Functions ---

backup_file() {
    local file_to_backup="$1"
    local backup_destination="$2"
    if [ -e "$file_to_backup" ]; then
        log_info "백업 파일 생성: $file_to_backup -> $backup_destination"
        if [ -d "$file_to_backup" ]; then
            cp -r "$file_to_backup" "$backup_destination" || log_error_and_exit "백업 디렉토리 생성 실패: $file_to_backup"
        else
            cp "$file_to_backup" "$backup_destination" || log_error_and_exit "백업 파일 생성 실패: $file_to_backup"
        fi
    fi
}

create_symlink() {
    local target="$1"
    local link_name="$2"

    if [ -L "$link_name" ]; then
        log_dim "기존 심볼릭 링크 제거: $link_name"
        rm "$link_name" || log_error_and_exit "기존 심볼릭 링크 제거 실패: $link_name"
    elif [ -f "$link_name" ] || [ -d "$link_name" ]; then
        log_warning "경고: $link_name 가 심볼릭 링크가 아닙니다. 백업 후 제거합니다."
        backup_file "$link_name" "${link_name}-$(date +%Y%m%d%H%M%S)-original"
        rm -rf "$link_name" || log_error_and_exit "기존 파일/디렉토리 제거 실패: $link_name"
    fi

    log_info "심볼릭 링크 생성: $link_name -> $target"
    ln -s "$target" "$link_name" || log_error_and_exit "심볼릭 링크 생성 실패: $link_name -> $target"
}

# --- Main Script Logic ---

log_debug "\n--- VS Code extensions dotfiles setup 시작 ---"

# .prettierrc 파일 존재 여부 확인
if [ ! -f "$PRETTIERRC_SOURCE" ]; then
    log_error_and_exit ".prettierrc 파일이 '${PRETTIERRC_SOURCE}' 경로에 존재하지 않습니다."
fi

# .prettierrc 심볼릭 링크 생성
create_symlink "$PRETTIERRC_SOURCE" "$HOME_PRETTIERRC"

# --- Verify Links ---

log_debug "\n--- 심볼릭 링크 확인 ---"

if [ -L "$HOME_PRETTIERRC" ]; then
    log_dim "✓ .prettierrc 심볼릭 링크 확인됨"
else
    log_error_and_exit ".prettierrc 심볼릭 링크 생성 실패"
fi

# --- Completion Messages ---

log_debug "--- VS Code extensions dotfiles setup 완료 ---"
echo ""

ux_success "VS Code extensions 설정이 완료되었습니다!"
ux_info "다음 설정이 적용되었습니다:"
ux_bullet "~/.prettierrc → ~/dotfiles/vscode-extensions/.prettierrc (symlink)"
echo ""

ux_section "다음 단계"
ux_bullet "VS Code를 재시작하여 Prettier 설정을 적용합니다"
ux_bullet "모든 프로젝트에서 자동 포맷팅 시 tabWidth: 4가 적용됩니다"
ux_bullet "필요시 설정 파일 편집: ${UX_BOLD}vim ~/dotfiles/vscode-extensions/.prettierrc${UX_RESET}"
echo ""

exit 0
