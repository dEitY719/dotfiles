# Claude Code environment variables
# Auto-mount configuration for Claude Code directories

# Auto-mount skills directory (bind mount ~/dotfiles/claude/skills → ~/.claude/skills)
export CLAUDE_AUTO_MOUNT_SKILLS=1

# Auto-mount agents directory (bind mount ~/dotfiles/claude/agents → ~/.claude/agents)
export CLAUDE_AUTO_MOUNT_AGENTS=1

# Auto-mount docs directory (bind mount ~/dotfiles/claude/docs → ~/.claude/docs)
export CLAUDE_AUTO_MOUNT_DOCS=1

# AI tool for documentation generation
# Options: claude (default), gemini, codex, or any CLI tool accepting -p/--prompt
# Can be overridden per-command or per-session
export CLAUDE_DOC_GENERATOR=claude
