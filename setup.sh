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

# Canonicalize to the main worktree (issue #589). Running ./setup.sh from a
# linked worktree would otherwise bake the worktree path into every
# ~/.claude-*/{settings.json, statusline-command.sh, skills, docs, ...}
# symlink. When the worktree is later removed those symlinks dangle and
# Claude Code silently reverts to defaults (no statusline, no hooks).
_DOTFILES_RESOLVER="${DOTFILES_DIR}/shell-common/functions/dotfiles_root.sh"
if [ -r "$_DOTFILES_RESOLVER" ]; then
    # shellcheck source=shell-common/functions/dotfiles_root.sh
    source "$_DOTFILES_RESOLVER"
    _CANONICAL=$(_resolve_dotfiles_root_canonical "$DOTFILES_DIR")
    if [ -n "$_CANONICAL" ] && [ "$_CANONICAL" != "$DOTFILES_DIR" ]; then
        echo "[setup.sh] 워크트리에서 실행됨 — 메인 워크트리로 전환: $_CANONICAL" >&2
        cd "$_CANONICAL"
        DOTFILES_DIR="$_CANONICAL"
    fi
    unset _CANONICAL
fi
unset _DOTFILES_RESOLVER

UX_LIB_SCRIPT="${DOTFILES_DIR}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "${UX_LIB_SCRIPT}" ]; then
    # shellcheck source=/dev/null
    source "${UX_LIB_SCRIPT}"
else
    echo "CRITICAL ERROR: UX library script not found at ${UX_LIB_SCRIPT}. Exiting." >&2
    exit 1
fi

# Neutralize any leftover git-crypt smudge/clean config (#594). Idempotent
# safety net — repo no longer encrypts files, but older PCs may still carry
# `filter.git-crypt.required=true` in their per-repo git config.
./scripts/disable-git-crypt-local.sh

# Run setup scripts for shell-common, bash, zsh, git, claude, and vscode-extensions
./shell-common/setup.sh
./bash/setup.sh
./zsh/setup.sh
./git/setup.sh
./obsidian/setup.sh            # Obsidian CLI wrapper → ~/.local/bin/obsidian (#1023)
./claude/setup.sh
./gemini/setup.sh
./aws/setup.sh                 # Internal-PC AWS Bedrock bootstrap (#677). No-op on external/public PCs.
./scripts/setup-skills-ssot.sh
./scripts/setup-company-skills.sh   # Private skills overlay (#707). No-op when COMPANY_SKILLS_HOME is missing.
./vscode-extensions/setup.sh
# Propagate .vscode/base.json (SSOT) to the live VS Code User settings.json (#586).
# Non-fatal: sync-push exits 1 when VS Code is absent on this host.
./.vscode/sync-push.sh || ux_warning ".vscode/sync-push.sh 건너뜀 (VS Code 미설치 또는 환경 미감지). 필요 시 수동 실행."
./ssh/setup.sh
./gh/setup.sh

# Post-setup integrity check (#594): JSON parse + NBSP/BOM/NUL scan on
# every config file setup.sh activated via symlink. Fails loud if any
# target file is corrupted.
./scripts/verify-config-files.sh

# Run setup scripts for vim and tmux

# ./vim/setup.sh

# ./tmux/setup.sh