#!/bin/zsh
# shellcheck disable=SC1071  # zsh script; shellcheck cannot parse zsh

# zsh/setup.sh: Zsh shell environment setup
#
# PURPOSE: Set up zsh shell and provide user guidance
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL FEATURES (why this file is REQUIRED):
#   1. Creates ~/.zshrc symlink to zsh/zshrc
#   2. Provides user feedback using UX library
#   3. Displays completion messages and next steps
#   4. Guides users on how to apply changes
#
# Note: While zsh/main.zsh is the main loader, this script ensures
# proper initialization and user communication during setup.
#
# See docs/guide/setup.md for more information

# --- Constants ---

# Initialize DOTFILES_ROOT and other paths
# Handle both bash and zsh execution contexts
if [ -n "${BASH_SOURCE[0]}" ]; then
    # Bash context
    DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
elif [ -n "${ZSH_VERSION}" ]; then
    # Zsh context: Use zsh-specific $0 (relative to script location)
    _THIS_SCRIPT="${(%):-%N}"
    DOTFILES_ROOT="$(cd "$(dirname "${_THIS_SCRIPT:-.}")/.." && pwd)"
else
    # Fallback
    DOTFILES_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

ZSH_DOTFILES="${DOTFILES_ROOT}/zsh"
ZSH_ZSHRC_SOURCE="${ZSH_DOTFILES}/zshrc"
HOME_ZSHRC="${HOME}/.zshrc"

# Tracks the backup path created when ~/.zshrc was replaced from a
# regular file to a symlink (issue #761). Empty when no backup was made.
ZSHRC_BACKUP_NOTICE_PATH=""

# Load UX library (unified library at shell-common/tools/ux_lib/)
UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    source "$UX_LIB"
else
    echo "Error: UX library not found at $UX_LIB"
    exit 1
fi

# Idempotent link + latest-only backup lib (#806, #2138). It also loads
# dotfiles_backup.sh (suffix SSOT) and the log_info/log_error/log_warning/
# log_error_and_exit shims used below.
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1

# --- Main Script Logic ---

ux_section "zsh dotfiles setup"

# zshrc 파일 존재 여부 확인
if [ ! -f "$ZSH_ZSHRC_SOURCE" ]; then
    log_error_and_exit "zshrc 파일이 '${ZSH_ZSHRC_SOURCE}' 경로에 존재하지 않습니다. 파일을 먼저 생성해주세요."
fi

# ~/.zshrc 를 심볼릭 링크로 생성 (일반 파일이면 .original 로 백업 — #761 안내 대상)
_zshrc_was_file=0
[ -e "$HOME_ZSHRC" ] && [ ! -L "$HOME_ZSHRC" ] && _zshrc_was_file=1
dotfiles_ensure_link "$ZSH_ZSHRC_SOURCE" "$HOME_ZSHRC" ||
    log_error_and_exit "심볼릭 링크 생성 실패: $HOME_ZSHRC"
if [ "$_zshrc_was_file" = 1 ] && [ -L "$HOME_ZSHRC" ]; then
    ZSHRC_BACKUP_NOTICE_PATH="${HOME_ZSHRC}${DOTFILES_ORIGINAL_SUFFIX}"
fi

# Seed ~/.zshrc.local (untracked, PC-specific overrides). Issue #737 —
# installer side-effects (bun, nvm, …) must NOT land in the tracked
# dotfile. We create the file once if it does not exist, and migrate
# any known bun init block if the host already runs bun (idempotent).
HOME_ZSHRC_LOCAL="${HOME}/.zshrc.local"
if [ ! -f "$HOME_ZSHRC_LOCAL" ]; then
    log_info "~/.zshrc.local 생성 (PC-specific overrides 용)"
    cat >"$HOME_ZSHRC_LOCAL" <<'EOF'
# ~/.zshrc.local — PC-specific overrides, NOT tracked in dotfiles.
# Installer-mutable lines (bun, nvm, pyenv, …) belong here so the
# tracked zsh/zshrc stays portable across machines. See issue #737.
EOF
fi

if [ -d "$HOME/.bun" ] && ! grep -q 'BUN_INSTALL' "$HOME_ZSHRC_LOCAL" 2>/dev/null; then
    log_info "기존 bun 설치 감지 — ~/.zshrc.local 에 bun init 블록 이관"
    cat >>"$HOME_ZSHRC_LOCAL" <<'EOF'

# bun (migrated from zsh/zshrc per issue #737)
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
EOF
fi

# --- Setup Powerlevel10k Configuration ---

# Powerlevel10k 설정 파일 symlink 생성
P10K_SOURCE="${ZSH_DOTFILES}/app/p10k.zsh"
HOME_P10K="${HOME}/.p10k.zsh"

if [ -f "$P10K_SOURCE" ]; then
    dotfiles_ensure_link "$P10K_SOURCE" "$HOME_P10K" ||
        log_error_and_exit "심볼릭 링크 생성 실패: $HOME_P10K"
else
    log_warning "경고: p10k.zsh 파일이 '${P10K_SOURCE}' 경로에 없습니다. ~/.p10k.zsh를 생성하지 않습니다."
fi

# --- Completion Messages ---

ux_success "zsh dotfiles setup 완료"
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

# Issue #761 — when ~/.zshrc was replaced from a regular file to a
# symlink, the backup is easy for users to forget. Surface it explicitly
# with a diff guide so external-installer lines (bun/nvm/pyenv init,
# etc.) can be migrated into ~/.zshrc.local before the backup is lost.
if [ -n "$ZSHRC_BACKUP_NOTICE_PATH" ]; then
    ux_section "~/.zshrc 백업 검토 필요"
    ux_info "설치 중 ~/.zshrc 일반 파일이 심볼릭 링크로 교체되었습니다."
    ux_bullet "백업: ${UX_BOLD}${ZSHRC_BACKUP_NOTICE_PATH}${UX_RESET}"
    echo ""
    ux_info "dotfiles 외부 도구가 추가한 줄이 있는지 확인:"
    ux_bullet "${UX_BOLD}diff ${ZSHRC_BACKUP_NOTICE_PATH} ${ZSH_ZSHRC_SOURCE}${UX_RESET}"
    echo ""
    ux_info "추가 설정은 다음 위치에 보관 권장:"
    ux_bullet "${UX_BOLD}~/.zshrc.local${UX_RESET} (PC-specific overrides)"
    ux_bullet "${UX_BOLD}shell-common/env/development.local.sh${UX_RESET}"
    echo ""
fi

exit 0
