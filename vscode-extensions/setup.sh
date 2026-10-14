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
# See docs/guide/setup.md for more information

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

# Idempotent link + latest-only backup lib (#806, #2138); also provides
# log_error_and_exit.
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
# shellcheck source=../shell-common/lib/setup/link.sh
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1

log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }

# --- Main Script Logic ---

ux_section "VS Code extensions dotfiles setup"

# .prettierrc 파일 존재 여부 확인
if [ ! -f "$PRETTIERRC_SOURCE" ]; then
    log_error_and_exit ".prettierrc 파일이 '${PRETTIERRC_SOURCE}' 경로에 존재하지 않습니다."
fi

# .prettierrc 심볼릭 링크 생성 (파일/디렉토리면 .prettierrc.original 로 백업)
dotfiles_ensure_link "$PRETTIERRC_SOURCE" "$HOME_PRETTIERRC" --allow-dir ||
    log_error_and_exit "심볼릭 링크 생성 실패: $HOME_PRETTIERRC"

# --- Verify Links ---

ux_section "심볼릭 링크 확인"

if [ -L "$HOME_PRETTIERRC" ]; then
    log_dim "✓ .prettierrc 심볼릭 링크 확인됨"
else
    log_error_and_exit ".prettierrc 심볼릭 링크 생성 실패"
fi

# --- Completion Messages ---

ux_success "VS Code extensions dotfiles setup 완료"
echo ""

ux_success "VS Code extensions 설정이 완료되었습니다!"
ux_info "다음 설정이 적용되었습니다:"
# shellcheck disable=SC2088  # display text, not a path
ux_bullet "~/.prettierrc → ~/dotfiles/vscode-extensions/.prettierrc (symlink)"
echo ""

ux_section "다음 단계"
ux_bullet "VS Code를 재시작하여 Prettier 설정을 적용합니다"
ux_bullet "모든 프로젝트에서 자동 포맷팅 시 tabWidth: 4가 적용됩니다"
ux_bullet "필요시 설정 파일 편집: ${UX_BOLD}vim ~/dotfiles/vscode-extensions/.prettierrc${UX_RESET}"
echo ""

exit 0
