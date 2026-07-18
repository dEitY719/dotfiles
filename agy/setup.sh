#!/bin/bash

# agy/setup.sh: Antigravity CLI (agy) environment setup
#
# PURPOSE: Verify the `agy` binary is installed and executable on PATH.
# WHEN TO RUN: Via ./setup.sh
#
# NOTE: Unlike gemini/setup.sh, this script creates NO symbolic links and
# NEVER modifies PATH or shell profiles. `agy` ships its own installer
# (`agy install`, with --skip-aliases / --skip-path) that edits shell
# profiles, and dotfiles already manages ~/.local/bin via the PATH SSOT
# (shell-common/env/path.sh). Touching PATH here would re-introduce the
# triple-managed PATH conflict this module was created to avoid (#1180).

# --- Constants ---

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

INSTALL_CMD="curl -fsSL https://antigravity.google/cli/install.sh | bash"

# Load UX library if available
UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    source "$UX_LIB"
    log_info() { ux_info "$1"; }
    log_error() { ux_error "$1"; }
    log_success() { ux_success "$1"; }
else
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
fi

# --- Setup Logic ---

if command -v agy >/dev/null 2>&1; then
    log_success "Antigravity CLI (agy) 확인됨: $(command -v agy)"
else
    log_info "Antigravity CLI (agy) 가 PATH 에서 발견되지 않았습니다."
    log_info "설치하려면 다음 공식 커맨드를 실행하세요:"
    log_info "  ${INSTALL_CMD}"
    log_info "(dotfiles 는 설치를 대신 실행하지 않습니다 — PATH SSOT 충돌 방지)"
fi

echo ""
log_success "Antigravity CLI dotfiles 설정이 완료되었습니다!"
exit 0
