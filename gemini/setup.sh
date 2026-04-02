#!/bin/bash

# gemini/setup.sh: Gemini CLI environment setup
#
# PURPOSE: Set up Gemini CLI configuration with symbolic links
# WHEN TO RUN: Via ./setup.sh

# --- Constants ---

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"
GEMINI_DOTFILES="${DOTFILES_ROOT}/gemini"

HOME_GEMINI="${HOME}/.gemini"
HOME_GEMINIMD="${HOME_GEMINI}/GEMINI.md"

GEMINI_GEMINIMD_SOURCE="${GEMINI_DOTFILES}/GEMINI.md"

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

if [ ! -d "$HOME_GEMINI" ]; then
    log_info "~/.gemini 디렉토리 생성"
    mkdir -p "$HOME_GEMINI" || { log_error "~/.gemini 디렉토리 생성 실패"; exit 1; }
fi

if [ -L "$HOME_GEMINIMD" ]; then
    if [ "$(realpath "$HOME_GEMINIMD")" == "$GEMINI_GEMINIMD_SOURCE" ]; then
        log_success "GEMINI.md 심볼릭 링크가 이미 올바르게 설정되어 있습니다."
    else
        log_info "기존 GEMINI.md 심볼릭 링크 업데이트"
        rm -f "$HOME_GEMINIMD"
        ln -sf "$GEMINI_GEMINIMD_SOURCE" "$HOME_GEMINIMD"
        log_success "GEMINI.md 심볼릭 링크 업데이트 완료."
    fi
elif [ -e "$HOME_GEMINIMD" ] || [ -L "$HOME_GEMINIMD" ]; then
    log_info "기존 GEMINI.md 항목 백업 및 심볼릭 링크 생성"
    mv "$HOME_GEMINIMD" "${HOME_GEMINIMD}.bak-$(date +%Y%m%d%H%M%S)"
    ln -sf "$GEMINI_GEMINIMD_SOURCE" "$HOME_GEMINIMD"
    log_success "GEMINI.md 백업 및 심볼릭 링크 생성 완료."
else
    log_info "GEMINI.md 심볼릭 링크 생성"
    ln -sf "$GEMINI_GEMINIMD_SOURCE" "$HOME_GEMINIMD"
    log_success "GEMINI.md 심볼릭 링크 생성 완료."
fi

echo ""
log_success "Gemini CLI dotfiles 설정이 완료되었습니다!"
