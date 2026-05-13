# Claude Code Configuration

## Overview

This directory contains configuration files for [Claude Code](https://claude.com/claude-code), Anthropic's CLI for working with Claude AI.

## Setup Instructions

### First Time Setup

`claude/settings.json` is the **tracked SSOT** (#584) — the same file is used on
Home, External, and Internal PCs. `./setup.sh` symlinks it to
`~/.claude/settings.json` automatically; no bootstrap copy step is needed.

### Internal PC — one-time env block

The shared SSOT cannot carry the Samsung internal `ANTHROPIC_*` env vars
because those values point at `cloud.dtgpt.samsungds.net` and would break
Claude Code on External / Home. Internal-PC users create a separate
per-machine override file (gitignored, out-of-repo) once:

```bash
mkdir -p ~/.claude && cat > ~/.claude/settings.local.json <<'JSON'
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://cloud.dtgpt.samsungds.net/llm",
    "ANTHROPIC_AUTH_TOKEN": "your-dt-api-key",
    "ANTHROPIC_MODEL": "Qwen3.6-27B"
  }
}
JSON
```

Then replace `your-dt-api-key` with the real token issued by the internal LLM
gateway team. Claude Code merges `~/.claude/settings.local.json` with
`~/.claude/settings.json` on every launch.

`claude/setup.sh` prints the same snippet at the end of Internal-mode setup
so you don't have to come back to this README.

Verify after editing:

```bash
jq -e .env.ANTHROPIC_AUTH_TOKEN ~/.claude/settings.local.json
```

### Customizing Shared Settings

Edit `claude/settings.json` to change behavior across all PCs:

- **Model** — `"model": "haiku" | "sonnet" | "opus"`
- **Status line** — `statusLine.command` points at the dotfiles SSOT script
  (`${HOME}/dotfiles/claude/statusline-command.sh`); works across multi-account
  `CLAUDE_CONFIG_DIR` targets without per-account symlinks (issue #296).
- **Hooks** — `Stop` / `PostToolUse` entries already wired for `gh:issue-flow`
  and `gh:pr` flows.
- **Plugins** — `enabledPlugins` controls which Claude plugins load.
- **Sandboxing / permissions** — add Claude Code permission rules here if you
  want them shipped across all your PCs; per-PC overrides go in the local
  override file.

## Important Notes

- `claude/settings.json` **IS** version controlled (this changed in #584).
  Hand-edits land in git history — keep it free of PII / tokens.
- Per-PC secrets (Knox ID, internal API tokens, machine-specific paths) go
  in `~/.claude/settings.local.json` — a regular file outside the repo,
  gitignored as defense-in-depth.

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
├── README.md                   # This file
├── settings.json               # Tracked SSOT (#584) — symlinked to ~/.claude/
├── setup.sh                    # Symlinks settings.json into ~/.claude/
├── statusline-command.sh       # Status-line renderer
├── hooks/                      # PreToolUse / PostToolUse / Stop hooks
└── skills/                     # Claude Code custom skills

~/.claude/settings.local.json   # Per-PC, gitignored, hand-created on Internal
```

## Resources

- [Claude Code Documentation](https://github.com/anthropics/claude-code)
- [Claude Agent SDK](https://github.com/anthropics/anthropic-sdk-python)
- [Claude Code Slash Commands](/help)
