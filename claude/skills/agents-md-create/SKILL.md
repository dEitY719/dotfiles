---
name: agents-md:create
description: >-
  Create a new AGENTS.md documentation system for a project from scratch. Use
  when the user says "create AGENTS.md", "set up my context file", "initialize
  project docs for AI", "I don't have an AGENTS.md yet", or "/agents-md:create".
  Generates root AGENTS.md and nested files as needed. Distinct from
  agents-md:refactor (existing file) and agents-md:check (audit only).
allowed-tools: Read, Glob, Grep, Write, Bash
---

# AGENTS.md Creator

## Workflow

### Phase 0: Discover (always run first)

```bash
# Detect project type
ls pyproject.toml package.json Cargo.toml go.mod 2>/dev/null
# Check for existing AGENTS.md
find . -name "AGENTS.md" -maxdepth 4
# Count files to gauge project size
find . -not -path './.git/*' -type f | wc -l
```

Classify project size:
- **Small**: <20 files, single tech stack → root AGENTS.md only
- **Medium**: 20–100 files, 2–3 tech domains → root + 2–3 nested files
- **Large**: 100+ files, multiple services → root + nested per service/domain

### Phase 1: Select Template

Read the appropriate template from `references/`:

| Size | Template file |
|------|--------------|
| Small | `references/small-project.md` |
| Medium | `references/medium-project.md` |
| Large | `references/large-project.md` |

### Phase 2: Fill Template

Replace all `<placeholder>` values with project-specific content discovered
in Phase 0. Operational commands must be real and executable — verify they
exist in the project before including them.

### Phase 3: Validate Before Writing

Mental checklist (fix before writing if any fail):
- [ ] Root AGENTS.md < 400 lines
- [ ] No emojis anywhere
- [ ] All commands are executable as-is
- [ ] Context Map uses list format (no tables)
- [ ] Naming conventions section present

### Phase 4: Write Files

Write root AGENTS.md first, then nested files. Report what was created.

## Output Report

```
## AGENTS.md Created

Root: ./AGENTS.md — <N> lines
Nested: <list or "none">

Validation: <pass count>/5 checks passed
Next: Run /agents-md:check to audit the result
```
