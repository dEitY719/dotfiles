#!/bin/bash

# setup.sh: Shell environment setup orchestrator
#
# PURPOSE: Set up all shell configurations (bash, zsh, git)
# WHEN TO RUN: On initial dotfiles installation (REQUIRED)
#
# This script orchestrates the setup of individual shell environments.
# Each sub-script performs specific initialization:
#   - bash/setup.sh: Sets DOTFILES_BASH_DIR, SHELL_COMMON environment variables
#   - zsh/setup.sh: Provides user feedback and guidance
#   - git/setup.sh: Sets up git configuration
#   - claude/setup.sh: Manages Claude Code settings via symlinks
#
# See SETUP_GUIDE.md for detailed information
#
# ⚠️  IMPORTANT: Do NOT delete bash/setup.sh, zsh/setup.sh, git/setup.sh, claude/setup.sh, or gh/setup.sh
#     They perform special initialization beyond simple symlink creation

set -e

# Load UX library so user-facing messages stay consistent (mirrors install.sh).
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UX_LIB_SCRIPT="${DOTFILES_DIR}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "${UX_LIB_SCRIPT}" ]; then
    # shellcheck source=/dev/null
    source "${UX_LIB_SCRIPT}"
else
    echo "CRITICAL ERROR: UX library script not found at ${UX_LIB_SCRIPT}. Exiting." >&2
    exit 1
fi

# Run setup scripts for shell-common, bash, zsh, git, claude, and vscode-extensions
./shell-common/setup.sh
./bash/setup.sh
./zsh/setup.sh
./git/setup.sh
./claude/setup.sh
./gemini/setup.sh
./scripts/setup-skills-ssot.sh
./vscode-extensions/setup.sh
# Propagate .vscode/base.json (SSOT) to the live VS Code User settings.json (#586).
# Non-fatal: sync-push exits 1 when VS Code is absent on this host.
./.vscode/sync-push.sh || ux_warning ".vscode/sync-push.sh 건너뜀 (VS Code 미설치 또는 환경 미감지). 필요 시 수동 실행."
./ssh/setup.sh
./gh/setup.sh



# Run setup scripts for vim and tmux

# ./vim/setup.sh

# ./tmux/setup.sh