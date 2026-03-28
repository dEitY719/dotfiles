# Module Context

- **Purpose**: Manage Claude Code CLI configuration, skills, and automation
- **Dependencies**: Claude Code CLI (@anthropic-ai/claude-code), jq, sudo
- **Ownership**: Personal dotfiles management

# Tech Stack & Constraints

- **Configuration**: JSON (settings.json), Bash (setup.sh, statusline-command.sh)
- **Skills Management**: Bind mount (~/dotfiles/claude/skills -> ~/.claude/skills)
- **Automation**: Shell function (claude_mount_skills) for auto-mounting
- **Permissions**: Sudoers configuration for passwordless bind mount

# Permission Modes

Claude Code supports the following permission modes in `settings.json`:

| Mode | Description | Use Case |
|------|-------------|----------|
| `default` | Request user approval on first tool use | Standard, security-focused |
| `acceptEdits` | Auto-accept file edit permissions | Trusted environments |
| `dontAsk` | Auto-deny except allow-listed tools | Minimal interruption |
| `plan` | Analysis-only mode (no modifications) | Planning & exploration |
| `bypassPermissions` | Skip all permission checks | CI/CD, sandboxed environments |

Set via CLI:
```bash
claude --permission-mode bypassPermissions
```

Or configure in `settings.json` (line 174):
```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
```

⚠️ **Warning**: `bypassPermissions` disables all security checks. Use only in trusted, isolated environments.

# Implementation Patterns

## Configuration Files

Settings are managed via symlinks and bind mount:

```bash
~/.claude/settings.json -> ~/dotfiles/claude/settings.json (symlink)
~/.claude/statusline-command.sh -> ~/dotfiles/claude/statusline-command.sh (symlink)
~/.claude/skills <- ~/dotfiles/claude/skills (bind mount)
```

## Setup Script (setup.sh)

Located at `claude/setup.sh`, creates symlinks and configures sudoers:

```bash
# Creates symlinks for settings and statusline
create_symlink "$CLAUDE_SETTINGS_SOURCE" "$HOME_SETTINGS"
create_symlink "$CLAUDE_STATUSLINE_SOURCE" "$HOME_STATUSLINE"

# Sets up bind mount permissions
setup_skills_mount
```

## Auto-Mount Function (claude.sh)

Located at `shell-common/tools/external/claude.sh`:

```bash
claude_mount_skills() {
    # Check if already mounted (using unified _is_mounted function)
    if _is_mounted "$skills_target"; then
        return 0
    fi

    # Perform bind mount
    sudo mount --bind "$skills_source" "$skills_target" 2>/dev/null
}
```

Called automatically on shell startup. Uses `_is_mounted()` from `mount.sh` for consistent mount checking across the system.

## Skills Directory Structure

```
claude/skills/
├── agents-md-check/    # AGENTS.md compliance auditor
├── agents-md-create/   # AGENTS.md generator (Progressive Disclosure)
│   ├── SKILL.md       # Workflow only (<100 lines)
│   └── references/    # Project-size templates (loaded on demand)
├── agents-md-refactor/ # AGENTS.md splitter and optimizer
├── cli-dev/           # CLI development workflow
├── req-define/        # Requirements definition
└── ...                # Other skills
```

Each skill requires:
- `SKILL.md` with frontmatter (`name`, `description`, `allowed-tools` or `compatibility.tools`)
- Optional `README.md` for documentation

Skill names use `{namespace}:{action}` colon notation (e.g. `agents-md:check`, `skill:refactor`).

## Sub-Agent Parallel Execution

When a skill or workflow has independent tasks, use the Agent tool to run them concurrently in a single message. This reduces wall-clock time and matches how `/simplify` runs 3 review agents in parallel.

**When to parallelize:**
- Tasks have no data dependency between them (output of one is not input to another)
- Each task produces a separate artifact (different files, different analysis)

**When NOT to parallelize:**
- Task B requires Task A's output (e.g., analysis must finish before writing summary)
- Tasks modify the same file

**Pattern — parallel agents in SKILL.md:**

```markdown
### Step N: Launch agents in parallel

Use the Agent tool to launch all agents concurrently in a single message.

#### Agent 1: <task description>
<what this agent does and writes>

#### Agent 2: <task description>
<what this agent does and writes>
```

**Example — `dissect-builtin` skill:**

| Agent | Task | Dependency |
|-------|------|-----------|
| Agent 1 | Analyze prompt + write README.md | Needs loaded prompt (from Step 1) |
| Agent 2 | Copy raw prompt to PROMPT.md | Needs loaded prompt (from Step 1) |

Both depend on Step 1 (load prompt) but not on each other → parallel.

# Testing Strategy

## Manual Verification

After setup or changes:

```bash
# 1. Verify symlinks
ls -la ~/.claude/settings.json
ls -la ~/.claude/statusline-command.sh

# 2. Verify bind mount
show_mnt                    # Show all Claude mounts
show_mnt ~/.claude/skills   # Show specific mount

# 3. Verify skills loaded
claude  # Start Claude Code
/skills  # Check skills list
```

## Configuration Changes

```bash
# Edit settings
vim ~/dotfiles/claude/settings.json

# Restart Claude Code to apply
# Changes to symlinked files take effect immediately
```

# Local Golden Rules

## Skills Management

- **DO**: Create skills in `~/dotfiles/claude/skills/` for version control
- **DO**: Use SKILL.md frontmatter format (`name`, `description`, `allowed-tools` or `compatibility.tools`)
- **DO**: Use `{namespace}:{action}` colon notation in skill `name` (e.g. `skill:check`, `agents-md:create`)
- **DO**: Write `description:` as either a single line or YAML multi-line scalar (`>-`) — multi-line is supported by the YAML parser
- **DO**: Keep SKILL.md under 100 lines — use `references/` and Progressive Disclosure to extract detail
- **DON'T**: Manually create files in `~/.claude/skills/` (managed by bind mount)
- **DON'T**: Use symlinks for skills directory (use bind mount instead)

## Setup Requirements

- **DO**: Run `./setup.sh` after cloning dotfiles to new machine
- **DO**: Ensure sudoers configuration exists for passwordless mount
- **DO**: Restart shell after setup to activate auto-mount
- **DON'T**: Manually edit `/etc/sudoers.d/claude-skills-mount`
- **DON'T**: Skip setup.sh and manually create symlinks

## Configuration Best Practices

- **DO**: Keep settings.json in version control
- **DO**: Use variables in sudoers config (${USER}, ${CLAUDE_SKILLS_SOURCE})
- **DO**: Test configuration changes in new shell before committing
- **DON'T**: Hardcode paths in configuration files
- **DON'T**: Commit API keys or sensitive data

# Knowledge/References

- Claude Code Documentation: https://code.claude.com/docs
- Skills Guide: https://code.claude.com/docs/en/skills
- Bind Mount: Linux filesystem feature for directory mounting
- Sudoers: `/etc/sudoers.d/` for fine-grained sudo permissions

# Operational Commands

```bash
# Setup (first time)
./setup.sh

# Edit settings
vim ~/dotfiles/claude/settings.json

# Edit statusline
vim ~/dotfiles/claude/statusline-command.sh

# Verify mount
show_mnt                    # Show all Claude mounts
show_mnt ~/.claude/skills   # Show specific mount

# Unmount (if needed)
sudo umount ~/.claude/skills

# Re-mount manually
addmnt ~/dotfiles/claude/skills ~/.claude/skills
```
