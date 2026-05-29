#!/bin/bash

# gh/setup.sh: GitHub CLI configuration setup
#
# PURPOSE: Set up gh CLI configuration symlinks
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL FEATURES:
#   1. Creates ~/.config/gh/config.yml symlink to gh/config.yml
#   2. gh aliases (e.g. `gh postponed`) are version-controlled via this file

DOTFILES_GH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GH_CONFIG_SOURCE="${DOTFILES_GH_DIR}/config.yml"
GH_CONFIG_DIR="${HOME}/.config/gh"
GH_CONFIG_TARGET="${GH_CONFIG_DIR}/config.yml"

UX_LIB_SCRIPT="${DOTFILES_GH_DIR}/../shell-common/tools/ux_lib/ux_lib.sh"

if [[ -f "${UX_LIB_SCRIPT}" ]]; then
    source "${UX_LIB_SCRIPT}"
else
    echo "CRITICAL ERROR: UX library script not found at ${UX_LIB_SCRIPT}. Exiting." >&2
    exit 1
fi

ux_header "GitHub CLI (gh) dotfiles setup 시작"

mkdir -p "$GH_CONFIG_DIR"

if [ -L "$GH_CONFIG_TARGET" ]; then
    rm "$GH_CONFIG_TARGET"
elif [ -f "$GH_CONFIG_TARGET" ]; then
    # Latest-only fixed suffix (issue #806) — overwrite one backup instead of
    # accumulating. SSOT: shell-common/functions/dotfiles_backup.sh
    BACKUP_PATH="${GH_CONFIG_TARGET}.original"
    rm -f "$BACKUP_PATH"
    ux_warning "기존 config.yml 백업: ${BACKUP_PATH}"
    mv "$GH_CONFIG_TARGET" "$BACKUP_PATH"
fi

ln -s "$GH_CONFIG_SOURCE" "$GH_CONFIG_TARGET" || { ux_error "심볼릭 링크 생성 실패"; exit 1; }
ux_success "심볼릭 링크 생성: $GH_CONFIG_TARGET -> $GH_CONFIG_SOURCE"

ux_success "GitHub CLI (gh) dotfiles setup 완료"
exit 0
