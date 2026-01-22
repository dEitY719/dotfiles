# Module Context
- **Purpose**: Project documentation, guides, AI agent prompts, and code reviews
- **Structure**: Master prompts, review documents, todo tracking
- **Key Files**:
  - `AGENTS_md_Master_Prompt.md` - AGENTS.md generation protocol (source for agents-md skill)
  - `abc-review-C.md` - SOLID principle review (Claude Opus 4.5)
  - `todo.txt` - Project task tracking

# Operational Commands
- **Review**: Open in Markdown previewer (VS Code, grip)
- **Count Lines**: `wc -l docs/*.md` (enforce <500 for AGENTS.md files)

# Documentation Standards

## Markdown Formatting
- **Headers**: Use ATX style (`#`, `##`, not underlines)
- **Lists**: Consistent markers (`-` for unordered, `1.` for ordered)
- **Code Blocks**: Always specify language (```bash, ```python, ```markdown)
- **Line Length**: No hard limit, but prefer <120 chars for readability
- **Links**: Use relative paths (`../bash/README.md`, not absolute)

## AGENTS.md Protocol
Based on `AGENTS_md_Master_Prompt.md` (in `docs/archive/`):
- 500-line hard limit per file
- No emojis (token efficiency)
- No tables for Context Maps (use lists)
- Action-based routing (intent, not implementation)
- SOLID principles enforcement (SRP, OCP, LSP, ISP, DIP)
- TDD mandate (test-first workflow)

## Review Document Format
Pattern: `abc-review-<Initial>.md`
- `abc-review-C.md` - Claude review
- `abc-review-CX.md` - ChatGPT review (placeholder)
- `abc-review-G.md` - Gemini review (placeholder)

Structure:
1. Reviewer info (model, date, scope)
2. Project structure summary
3. SOLID principle evaluation (score /10 per principle)
4. Issues categorized by severity (high, medium, low)
5. Action items with priority
6. Conclusion and total score

# Golden Rules

## Documentation Maintenance
- **DO**: Update docs when code changes (especially AGENTS.md Context Maps)
- **DO**: Use consistent terminology across all docs
- **DO**: Include concrete examples (code snippets, commands)
- **DON'T**: Leave TODO markers without tracking (move to todo.txt)
- **DON'T**: Archive without documenting reason (use `archive/` with README)

## Master Prompt Modifications
- **Critical File**: `AGENTS_md_Master_Prompt.md` (archived at `docs/archive/AGENTS_md_Master_Prompt.md`) governs AGENTS.md generation
- **Change Protocol**:
  1. Backup existing version: `cp docs/archive/AGENTS_md_Master_Prompt.md docs/archive/AGENTS_md_Master_Prompt_v<date>.md`
  2. Update master prompt in archive
  3. Regenerate `~/.claude/skills/agents-md/SKILL.md` from updated master
  4. Test on sample project before applying to dotfiles
- **Version Suffix**: `_C` (Claude), `_CX` (ChatGPT), `_G` (Gemini)
- **Note**: Master prompt is archived but still governs the skill and documentation protocol

## Review Workflow
After implementing changes from reviews:
1. Mark items as completed in review doc (add checkboxes)
2. Update root AGENTS.md if Golden Rules changed
3. Commit with reference to review item (e.g., "Fix: Issue #3 from abc-review-C")

# File Descriptions

## AGENTS_md_Master_Prompt.md (15,511 bytes) [in docs/archive/]
Master protocol for AGENTS.md system generation (archived):
- 10 phases (Analysis, Root Gen, Nested Gen, Validation, etc.)
- SOLID & TDD enforcement
- Token efficiency rules (no emojis, lists not tables)
- 500-line limit with auto-split logic
- Error handling and rollback mechanisms
- **Note**: This is the canonical reference; kept in archive/ for version control

## abc-review-C.md (13,147 bytes)
Claude Opus 4.5 SOLID review of dotfiles:
- Overall score: 43/50 (Excellent)
- 9 identified issues (severity: high=2, medium=5, low=2)
- Implemented fixes: Problem 1, 2, 4, 5, 6, 7 (6/9 complete)
- Pending: Problem 3 (already resolved), 8, 9

## todo.txt (5,588 bytes)
Project task tracking (plain text format):
- Completed items
- Pending improvements
- Long-term refactoring ideas

# Testing Strategy

## AGENTS.md Validation
```bash
# Check line counts (must be <500)
wc -l **/AGENTS.md

# Validate no emojis
grep -r "[\u{1F300}-\u{1F9FF}]" **/AGENTS.md

# Check relative paths
grep -r "http://\|https://\|file://" **/AGENTS.md
```

# Maintenance

## Adding New Documentation
1. Create file in `docs/` with descriptive name
2. Add entry to this AGENTS.md under "File Descriptions"
3. Update root AGENTS.md Context Map if major doc

## Updating Master Prompt
See "Master Prompt Modifications" in Golden Rules above.

## Archiving Outdated Docs
```bash
# Create archive directory
mkdir -p docs/archive

# Move with explanation
mv docs/old-guide.md docs/archive/
echo "Archived: Replaced by new-guide.md (2026-01-01)" >> docs/archive/README.md
```

# Context Map
- **[Parent Context](../AGENTS.md)** — Project root and TDD protocol
- **[Bash Documentation](../bash/README.md)** — Detailed bash module docs
- **[Shell Common](../shell-common/AGENTS.md)** — Shared utilities context
