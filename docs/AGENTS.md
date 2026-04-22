# Module Context
- **Purpose**: Project documentation, guides, AI agent prompts, and code reviews
- **Structure**: Master prompts, feature docs, review documents, todo tracking
- **Key Files**:
  - `AGENTS_md_Master_Prompt.md` - AGENTS.md generation protocol (source for agents-md skill)
  - `standards/command-guidelines.md` - Command/help interface and output formatting SSOT
  - `standards/github-project-board.md` - GitHub Project kanban board workflow SSOT
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
- **DO**: Group feature-specific docs under `docs/feature/<feature-name>/`
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

## Learnings vs Technic vs Memory (Boundary Rules)
Four knowledge locations have distinct roles. Do not duplicate content — link instead.
- **`docs/learnings/`**: Short reusable patterns/snippets (50–80 lines target) learned from actual PR/commit experience. Korean by default (for human teammates).
- **`docs/technic/`**: Verified stack-centric technical docs (hundreds of lines). Full setup + tradeoffs.
- **`docs/standards/`**: Project SSOTs and decision records.
- **`memory/` (Claude-private)**: Cross-session context for AI. Entries should use pointers to `docs/learnings/` rather than duplicating content.

## Learnings Reference-Linking Rule
Every `docs/learnings/*.md` file SHOULD include traceability to its origin:
- **PR number** (most stable, survives merges): `PR #130`
- **Commit hash**: for pointing at a specific code example
- **Issue number**: when related discussion/bug exists
- **Review comment URL**: when the insight came from a bot/human review

If no such reference is possible (local experiment, conversation-only discovery), omit the links but record the **situation** in the Context section concretely.

## Language Policy for Docs
- **Human-teammate docs** (learnings/, technic/ narrative, standards/): Korean
- **AI-instruction docs** (SKILL.md, system prompts, machine-read templates): English

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

## docs/feature/<feature-name>/ (feature bundles)
Feature-centric documentation bundles:
- `README.md` - Feature index and reading order
- `analysis/` - Discovery, legacy analysis, category breakdowns
- `planning/` - Roadmaps, phase detail, progress tracking, quick start
- `requirements/` - REQ and design specification documents

## docs/learnings/ (reusable-pattern knowledge base)
Short snippets (50–80 lines) of reusable patterns extracted from real PRs/commits.
- `README.md` - Index + authoring rules + boundary vs technic/standards/memory
- Per-topic files follow 5-section template: Context / Pattern / Code / When to use / Related
- See "Learnings Reference-Linking Rule" and "Language Policy for Docs" in Golden Rules above

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
2. If it is feature-specific, place it under `docs/feature/<feature-name>/`
3. Add entry to this AGENTS.md under "File Descriptions"
4. Update root AGENTS.md Context Map if major doc

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
- **[Learnings](./learnings/README.md)** — Reusable pattern snippets from actual PRs
