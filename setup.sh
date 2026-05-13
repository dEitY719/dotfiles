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
./.vscode/sync-push.sh || echo "Warning: .vscode/sync-push.sh 건너뜀 (VS Code 미설치 또는 환경 미감지). 필요 시 수동 실행."
./ssh/setup.sh
./gh/setup.sh



# Run setup scripts for vim and tmux

# ./vim/setup.sh

# ./tmux/setup.sh