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
# These environment variables are CRITICAL
# for bash shell initialization to work properly.
#
# See docs/guide/setup.md for more information

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

# Idempotent link + latest-only backup lib (#806, #2138). It also loads
# dotfiles_backup.sh (suffix SSOT) and the log_info/log_error/log_warning/
# log_error_and_exit shims; only the bash-specific loggers stay below.
# shellcheck source=../shell-common/lib/setup/link.sh
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1

# Define legacy mapping functions for backward compatibility
log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }
# [DEBUG] 접두 출력은 명시적으로 DOTFILES_DEBUG=1 일 때만 노출 (#793 F-3).
log_debug() {
    [ "${DOTFILES_DEBUG:-0}" = "1" ] || return 0
    printf "%s[DEBUG] %s%s\n" "${UX_MUTED}" "$1" "${UX_RESET}"
}

# --- Main Script Logic ---

ux_section "dotfiles setup"

# main.bash 파일 존재 여부 확인

if [ ! -f "$MAIN_BASH_SOURCE" ]; then

    log_error_and_exit "main.bash 파일이 '${MAIN_BASH_SOURCE}' 경로에 존재하지 않습니다. 파일을 먼저 생성해주세요."

fi

# ~/.bashrc 로 심볼릭링크

dotfiles_ensure_link "$MAIN_BASH_SOURCE" "$HOME_BASHRC" ||
    log_error_and_exit "심볼릭 링크 생성 실패: $HOME_BASHRC"

# Seed ~/.bashrc.local (untracked, PC-specific overrides). Issue #1290 —
# mirrors the zsh pattern from issue #737. Installer/hook side-effects
# (bun, nvm, …) must NOT land in the tracked dotfile.
# We create the file once if it does not exist; existing content is never
# touched (idempotent).

HOME_BASHRC_LOCAL="${HOME}/.bashrc.local"

if [ ! -f "$HOME_BASHRC_LOCAL" ]; then

    log_info "${HOME_BASHRC_LOCAL} 생성 (PC-specific overrides 용)"

    cat >"$HOME_BASHRC_LOCAL" <<'EOF'
# ~/.bashrc.local — PC-specific overrides, NOT tracked in dotfiles.
# Installer-mutable lines (bun, nvm, pyenv, …) belong here so the
# tracked bash/main.bash stays portable across machines. See issue #1290.
EOF

fi

# ~/.bash_profile도 심볼릭링크 (선택 사항)

if [ -f "${DOTFILES_BASH_DIR}/profile.bash" ]; then

    log_dim "profile.bash 파일이 존재하므로 ~/.bash_profile 심볼릭 링크를 생성합니다."

    dotfiles_ensure_link "${DOTFILES_BASH_DIR}/profile.bash" "$HOME_BASH_PROFILE" ||
        log_error_and_exit "심볼릭 링크 생성 실패: $HOME_BASH_PROFILE"

else

    log_error "경고: ${DOTFILES_BASH_DIR}/profile.bash 파일이 없습니다. ~/.bash_profile 심볼릭 링크를 생성하지 않습니다."

fi

# Setup work_log.txt symlink (multi-PC sync)
# Points: ~/work_log.txt → para/archive/playbook/logs/work_log.txt
# SSOT: Symlink target declared in shell-common/config/symlinks.conf
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
    elif [ ! -d "$WORK_LOG_LINK" ]; then
        # Regular file -> backed up to work_log.txt.original, then linked
        dotfiles_ensure_link "$WORK_LOG_SRC" "$WORK_LOG_LINK" ||
            log_error_and_exit "심볼릭 링크 생성 실패: $WORK_LOG_LINK"
    fi
fi

# NOTE (issue #806): the former `_add_zshrc_auto_cleanup` runtime hook was
# removed. It prepended cleanup code via `cat ... > .new && mv .new ~/.zshrc`,
# which converted the dotfiles-managed ~/.zshrc symlink into a regular file.
# The next ./setup.sh run then re-backed-up and re-linked it, accumulating one
# backup per run.
#
# NOTE (issue #1809): its sibling `_cleanup_broken_zsh_plugins` (build-time,
# not a runtime hook) was removed too. `zsh/zshrc` already builds `plugins`
# dynamically from directory existence, so a registered-but-uninstalled
# plugin entry can't occur — the function's premise was false, and its
# string-based `sed` removal corrupted `zsh/zshrc` content whenever it ran
# (broke the `zsh-autosuggestions` system-fallback guard).

ux_success "dotfiles setup 완료"

log_dim "변경 사항을 적용하려면 'source ~/.bashrc' 또는 셸을 재시작하십시오."

log_dim "만약 ~/.bash_profile도 새로 링크했다면 'source ~/.bash_profile' 하거나 로그인 셸을 재시작하십시오."

exit 0
