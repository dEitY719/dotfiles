# AGENTS.md System Generator Skill

This Claude Code skill automatically generates and maintains AGENTS.md documentation systems following SOLID principles and TDD methodology.

## Installation

Already installed at: `~/.claude/skills/agents-md/`

This is a **personal skill** - available across all your projects.

## Usage

### Automatic Invocation (Recommended)

Claude will automatically use this skill when you mention:
- "Create AGENTS.md documentation"
- "Set up project context files"
- "Generate AI agent documentation"
- "Update AGENTS.md system"

### Manual Invocation

If Claude doesn't automatically invoke the skill, you can explicitly request:

```
Use the agents-md skill to create documentation for this project
```

## What This Skill Does

1. **Analyzes** your project structure (tech stack, dependencies, boundaries)
2. **Generates** root AGENTS.md with:
   - Project context and tech stack
   - Operational commands (dev, test, build, lint)
   - Golden Rules (Do's & Don'ts)
   - SOLID & TDD protocols
   - Context Map (hierarchical navigation)
3. **Creates nested** AGENTS.md files for:
   - Framework boundaries (frontend, backend)
   - Module-specific contexts (API routes, components, database)
4. **Validates** all files:
   - <500 line limit (hard stop)
   - No emojis (token efficiency)
   - No tables in Context Maps
   - TDD and SOLID compliance

## Example Output

After running, you'll get:

```
./AGENTS.md                          # Root context (routing & standards)
./frontend/AGENTS.md                 # React/UI context
./backend/AGENTS.md                  # FastAPI/routes context
./backend/api/AGENTS.md              # API-specific patterns
./tests/AGENTS.md                    # Testing strategy
```

Each file includes:
- Module purpose and dependencies
- Implementation patterns (code templates)
- Testing strategy (targeted commands)
- Local Golden Rules

## Key Features

### Token Efficiency
- No emojis (save 2-4 tokens each)
- Lists instead of tables (40% more compact)
- Concise, imperative language

### SOLID Compliance
- SRP: Each file = one responsibility
- OCP: Extensible via nested files
- DIP: Action-based routing (not implementation-bound)

### TDD Enforcement
- "No implementation without failing test" rule
- Targeted test commands (avoid slow full suites)
- 90%+ coverage for critical paths

### Quality Gates
- Auto-split if >500 lines
- Backup before overwrite
- Circular reference detection
- Validation checklist

## Verification

Check if skill is loaded:

```bash
# List all skills
ls ~/.claude/skills/

# Check SKILL.md
cat ~/.claude/skills/agents-md/SKILL.md

# Verify line count (must be <500)
wc -l ~/.claude/skills/agents-md/SKILL.md
```

## Troubleshooting

**Skill not being used:**
- Mention "AGENTS.md" explicitly in your request
- Ask: "Can you use the agents-md skill?"
- Verify YAML frontmatter is valid (no tabs)

**Invalid output:**
- Check project has recognizable structure (package.json, pyproject.toml, etc.)
- Ensure project has >10 files (minimum for nested generation)

**Line limit exceeded:**
- Skill will auto-split into nested files
- Check validation report for split locations

## Configuration

Edit `~/.claude/skills/agents-md/SKILL.md` to customize:
- `allowed-tools`: Add/remove tool permissions
- Execution Protocol: Modify phases
- Validation rules: Adjust thresholds

## Updates

To update this skill:

```bash
# Edit the SKILL.md
vim ~/.claude/skills/agents-md/SKILL.md

# Restart Claude Code or start new conversation
```

## Support

Based on: `docs/AGENTS_md_Master_Prompt.md`

For issues or improvements, refer to the master prompt documentation.

---

**Version**: 1.0.0
**Created**: 2026-01-01
**License**: Personal use
