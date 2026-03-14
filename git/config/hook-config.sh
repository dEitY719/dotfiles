#!/usr/bin/env bash
# git/config/hook-config.sh
#
# Single Source of Truth (SSOT) for hook configuration:
# - Regex patterns
# - Thresholds
# - Pathspec exclusions
#
# This file is sourced by:
# - git/global-hooks/pre-commit (user-level hook wrapper)
# - git/hooks/pre-commit (project-level hook runner)

# ─────────────────────────────────────────────────────────────────────────────
# Global hook (git/global-hooks/pre-commit)
# ─────────────────────────────────────────────────────────────────────────────

# Secret/key content detection (index content via git grep --cached)
GIT_HOOKS_FORBIDDEN_KEYS_ERE="${GIT_HOOKS_FORBIDDEN_KEYS_ERE:------BEGIN OPENSSH PRIVATE KEY-----|-----BEGIN RSA PRIVATE KEY-----|-----BEGIN PRIVATE KEY-----|AKIA[0-9A-Z]{16}}"

# Conflict markers (strict to reduce false positives)
GIT_HOOKS_CONFLICT_MARKERS_ERE="${GIT_HOOKS_CONFLICT_MARKERS_ERE:-^(<<<<<<<([[:space:]]|$)|=======[[:space:]]*$|>>>>>>>([[:space:]]|$))}"

# Debug code patterns (keep conservative; avoid matching generic terms)
GIT_HOOKS_DEBUG_PATTERNS_ERE="${GIT_HOOKS_DEBUG_PATTERNS_ERE:-pdb\\.set_trace\\(\\)|binding\\.pry|^[[:space:]]*debugger;|breakpoint\\(\\)}"

# Exclusions for debug-code scan (pathspecs for git grep)
# - Exclude docs and shell scripts (shell often contains "breakpoint()" in comments)
# - Exclude hook files themselves
GIT_HOOKS_DEBUG_GREP_EXCLUDES=(
  ':!*.md' ':!*.txt' ':!*.json' ':!*.yaml' ':!*.yml' ':!*.sh'
  ':!git/global-hooks/pre-commit' ':!git/hooks/pre-commit'
)

# Forbidden filename detection (basename/path + env allowlist)
GIT_HOOKS_FORBIDDEN_BASENAME_ERE="${GIT_HOOKS_FORBIDDEN_BASENAME_ERE:-^(\\.git-credentials|credentials\\.json|private\\.key|secret\\.key|id_rsa|id_dsa|id_ed25519|.*\\.pem)$}"
GIT_HOOKS_ENV_BASENAME_BLOCK_ERE="${GIT_HOOKS_ENV_BASENAME_BLOCK_ERE:-^\\.env(\\..*)?$}"
GIT_HOOKS_ENV_BASENAME_ALLOW_ERE="${GIT_HOOKS_ENV_BASENAME_ALLOW_ERE:-^\\.env\\.([^.]+\\.)*(example|sample|template|dist)$}"
GIT_HOOKS_FORBIDDEN_PATH_ERE="${GIT_HOOKS_FORBIDDEN_PATH_ERE:-(^|/)\\.aws/(credentials|config)$}"

# Large file threshold
GIT_HOOKS_LARGE_FILE_BYTES="${GIT_HOOKS_LARGE_FILE_BYTES:-10485760}" # 10MB

# ─────────────────────────────────────────────────────────────────────────────
# Project hook (git/hooks/pre-commit) / modules
# ─────────────────────────────────────────────────────────────────────────────

# Shebang expectations by directory
DOTFILES_HOOKS_SHEBANG_SHELL_COMMON="${DOTFILES_HOOKS_SHEBANG_SHELL_COMMON:-#!/bin/sh}"
DOTFILES_HOOKS_SHEBANG_SHELL_COMMON_CUSTOM="${DOTFILES_HOOKS_SHEBANG_SHELL_COMMON_CUSTOM:-#!/bin/bash}"
DOTFILES_HOOKS_SHEBANG_BASH="${DOTFILES_HOOKS_SHEBANG_BASH:-#!/bin/bash}"
DOTFILES_HOOKS_SHEBANG_ZSH="${DOTFILES_HOOKS_SHEBANG_ZSH:-#!/bin/zsh}"

# Library purity: installation commands not allowed at top-level
DOTFILES_HOOKS_LIBRARY_PURITY_INSTALL_ERE="${DOTFILES_HOOKS_LIBRARY_PURITY_INSTALL_ERE:-apt-get[[:space:]]+install|apt[[:space:]]+install|dnf[[:space:]]+install|yum[[:space:]]+install|pacman[[:space:]]+-S|pip[[:space:]]+install|uv[[:space:]]+pip[[:space:]]+install|npm[[:space:]]+install|brew[[:space:]]+install}"

# tools/custom auto-exec: tail window sizes
DOTFILES_HOOKS_CUSTOM_MAIN_TAIL_LINES="${DOTFILES_HOOKS_CUSTOM_MAIN_TAIL_LINES:-30}"
DOTFILES_HOOKS_CUSTOM_GUARD_TAIL_LINES="${DOTFILES_HOOKS_CUSTOM_GUARD_TAIL_LINES:-80}"
