# Claude Code Configuration

## Overview

This directory contains configuration files for [Claude Code](https://claude.com/claude-code), Anthropic's CLI for working with Claude AI.

## Setup Instructions

### First Time Setup

After cloning this repository, create your personal Claude Code settings:

```bash
cp claude/settings.template.json claude/settings.json
```

### Customizing Your Settings

Edit `claude/settings.json` to match your personal environment:

**Key customizations:**

1. **Model selection** - Choose your preferred model (e.g., `haiku`, `sonnet`, `opus`)
   ```json
   "model": "haiku"
   ```

2. **Permissions** - Add bash commands or tools you frequently use in the `allow` array
   ```json
   "permissions": {
     "allow": [
       "Bash(your-command:*)",
       // ... more permissions
     ]
   }
   ```

3. **Status Line** - Configure how Claude Code displays status information.
   The dotfiles SSOT path works across all multi-account `CLAUDE_CONFIG_DIR`
   targets (e.g. `~/.claude-personal`, `~/.claude-work`) without depending on
   per-account symlinks. See issue #296.
   ```json
   "statusLine": {
     "type": "command",
     "command": "${HOME}/dotfiles/claude/statusline-command.sh"
   }
   ```

4. **Plugins** - Enable/disable Claude Skills
   ```json
   "enabledPlugins": {
     "document-skills@anthropic-agent-skills": true,
     "example-skills@anthropic-agent-skills": true
   }
   ```

## Important Notes

- **`claude/settings.json` is NOT version controlled** - It contains personal, environment-specific settings
- **`claude/settings.template.json`** - Shared template with basic, team-friendly defaults
- Use relative paths (e.g., `./script.sh`) instead of absolute paths when possible for better team compatibility

## SKILL.md Writing Rules

### description must be a single line

The `description` field in SKILL.md YAML frontmatter **MUST be written on a single line**.
The `claude-skills` command (`get_claude_skills`) uses `grep '^description:'` to extract it,
so multi-line YAML syntax (`>`, `|`, or line continuations) will break the display.

```yaml
# WRONG - folded scalar, shows only ">" in claude-skills output
description: >
  Create beautiful visualizations...

# WRONG - literal scalar, shows only "|"
description: |
  Create beautiful visualizations...

# CORRECT - single line (can be long, truncated at 60 chars for display)
description: Create beautiful visualizations from any content or idea. Use for slide decks, dashboards, diagrams, and more.
```

> **History**: This issue has occurred 3 times (as of 2026-03-23). Each time a new skill was added
> with multi-line YAML description, causing the `claude-skills` listing to show broken output.

## File Structure

```
claude/
├── README.md                    # This file
├── settings.template.json       # Team defaults (version controlled)
├── settings.json               # Your personal settings (ignored by git)
└── skills/                     # Claude Code custom skills
```

## Resources

- [Claude Code Documentation](https://github.com/anthropics/claude-code)
- [Claude Agent SDK](https://github.com/anthropics/anthropic-sdk-python)
- [Claude Code Slash Commands](/help)
