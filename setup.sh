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
# ⚠️  IMPORTANT: Do NOT delete bash/setup.sh, zsh/setup.sh, git/setup.sh, or claude/setup.sh
#     They perform special initialization beyond simple symlink creation

set -e

# Run setup scripts for shell-common, bash, zsh, git, and claude
./shell-common/setup.sh
./bash/setup.sh
./zsh/setup.sh
./git/setup.sh
./claude/setup.sh



# Run setup scripts for vim and tmux

# ./vim/setup.sh

# ./tmux/setup.sh