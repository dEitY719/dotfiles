#!/bin/sh
# shell-common/env/claude.sh
# Claude Code environment variables
# Auto-mount configuration for Claude Code directories

# Legacy auto-mount of ~/.claude/{skills,docs}. After multi-account
# migration (issue #287), ~/.claude/ is the empty guard directory and
# bind mounts go to ~/.claude-{personal,work}/{skills,docs} via
# claude_accounts_init. Disable legacy auto-mount when migrated state
# is detected so we don't mount onto the guard dir.
if [ -d "$HOME/.claude-personal" ] || [ -d "$HOME/.claude-work" ]; then
    export CLAUDE_AUTO_MOUNT_SKILLS=0
    export CLAUDE_AUTO_MOUNT_DOCS=0
else
    export CLAUDE_AUTO_MOUNT_SKILLS=1
    export CLAUDE_AUTO_MOUNT_DOCS=1
fi

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
