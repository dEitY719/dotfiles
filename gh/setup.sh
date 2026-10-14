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

SHELL_COMMON="$(cd "${DOTFILES_GH_DIR}/.." && pwd)/shell-common"
# shellcheck source=../shell-common/lib/setup/link.sh
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1

ux_header "GitHub CLI (gh) dotfiles setup 시작"

# Same link -> no-op; real file -> backed up to config.yml.original (#806, #2138).
dotfiles_ensure_link "$GH_CONFIG_SOURCE" "$GH_CONFIG_TARGET" || exit 1
ux_success "심볼릭 링크: $GH_CONFIG_TARGET -> $GH_CONFIG_SOURCE"

ux_success "GitHub CLI (gh) dotfiles setup 완료"
exit 0
