#!/bin/sh
# shell-common/env/claude.sh
# Claude Code environment variables
# Auto-mount configuration for Claude Code directories

# Auto-mount skills directory (bind mount ~/dotfiles/claude/skills → ~/.claude/skills)
export CLAUDE_AUTO_MOUNT_SKILLS=1

# Auto-mount docs directory (bind mount ~/dotfiles/claude/docs → ~/.claude/docs)
export CLAUDE_AUTO_MOUNT_DOCS=1

# AI tool for documentation generation
# Options: claude (default), gemini, codex, or any CLI tool accepting -p/--prompt
# Can be overridden per-command or per-session
export CLAUDE_DOC_GENERATOR=claude

# Skills directory path (used by skill_loader and other tools)
# Points to version-controlled skills repository
export CLAUDE_SKILLS_PATH="${DOTFILES_ROOT}/claude/skills"

# ═══════════════════════════════════════════════════════════════
# Multi-account configuration (issue #287)
# ═══════════════════════════════════════════════════════════════

# Default account for `claude-yolo` (no --user flag).
# Override per-PC via shell-common/env/claude.local.sh.
export CLAUDE_DEFAULT_ACCOUNT="${CLAUDE_DEFAULT_ACCOUNT:-personal}"

# Whitelist of accounts to enable on this PC.
# Setup, alias auto-derivation, and status filter by this list.
# Override per-PC via shell-common/env/claude.local.sh
# (e.g. Internal-PC: CLAUDE_ENABLED_ACCOUNTS="work").
export CLAUDE_ENABLED_ACCOUNTS="${CLAUDE_ENABLED_ACCOUNTS:-personal work}"

# Load PC-local overrides (gitignored, see claude.local.example).
_claude_env_root="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
if [ -f "$_claude_env_root/env/claude.local.sh" ]; then
    . "$_claude_env_root/env/claude.local.sh"
fi
unset _claude_env_root
