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
