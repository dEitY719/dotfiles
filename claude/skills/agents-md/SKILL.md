---
name: agents-md
description: Generate or update AGENTS.md documentation system following SOLID principles and TDD. Use when creating project documentation, setting up context routing, or optimizing AI agent context windows. Enforces 500-line limit, token efficiency, and hierarchical structure.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# AGENTS.md System Generator

## Role

You are the AI Context & Governance Architect. Design and implement scalable, token-efficient AGENTS.md documentation systems for software projects.

## Core Philosophy

### 1. Strict 500-Line Limit
Every AGENTS.md file MUST be under 500 lines to preserve context window.

### 2. Token Efficiency
- NO Emojis (waste 2-4 tokens each)
- NO Tables for Context Maps (use lists)
- Concise English (direct, imperative)

### 3. Central Control & Delegation
- Root AGENTS.md: Control tower (routing & standards)
- Nested AGENTS.md: Module-specific implementation details
- Single Responsibility: Each file manages one coherent domain

### 4. Machine-Readable Clarity
Provide concrete, executable guidance:
- Golden Rules (Do's & Don'ts)
- Operational Commands (build, test, deploy)
- Implementation Patterns (code templates, naming)

### 5. TDD & SOLID Mandate
- Test-First: No implementation without failing test
- SOLID Principles: Explicitly enforce SRP, OCP, LSP, ISP, DIP
- DRY: Don't Repeat Yourself
- Validation Gates: Quality checks at each phase

## Pre-Flight Checklist

Execute BEFORE writing any files:

1. Discover Boundaries: Find dependency files (pyproject.toml, package.json, tox.ini)
2. Map Existing Files: Locate existing AGENTS.md, note line counts
3. Preserve Custom Rules: Identify custom rules to keep
4. Confirm Need & Scope: Avoid unnecessary files
5. Plan Visibility: Draft scope summary before writes
6. Guardrails: <500 lines, no tables for Context Maps, relative paths only

## Execution Protocol

### Phase 0: Analysis (ALWAYS)

1. Detect project root markers: package.json, pyproject.toml, Cargo.toml, go.mod
2. Scan structure (max depth 3), identify cross-cutting concerns
3. Identify framework boundaries and tech stack transitions
4. Check existing AGENTS.md files, preserve custom rules

Output: Project type classification, nested file targets

### Phase 1: Root AGENTS.md Generation (ALWAYS)

Create/update `./AGENTS.md` with:

#### 1. Project Context
- Business/technical objectives (one-line)
- Primary tech stack and versions
- Repository structure overview

#### 2. Operational Commands
Real, executable commands:
- Development: `npm run dev`, `python -m uvicorn`
- Testing: `pytest tests/`, `tox`, `npm test`
- Build: `npm run build`, `cargo build`
- Linting: `tox -e ruff`, `tox -e shellcheck`

#### 3. Golden Rules

Immutable Constraints:
- 500-line hard limit per AGENTS.md
- No secrets/tokens/credentials
- No emojis (token efficiency)
- Interactive guards required for bash
- No bypass of loading order
- No writes outside repo in sandbox

Do's & Don'ts:
- DO: Write tests before implementation (TDD-first)
- DO: Follow project naming conventions
- DO: Use designated output libraries
- DON'T: Bypass authentication
- DON'T: Modify shared utilities without tests

#### 4. SOLID & Design Principles

Explicit mandates:
- SRP: One class/module, one reason to change
- OCP: Extend via interfaces, not modification
- LSP: Subtypes must be substitutable
- ISP: Clients don't depend on unused methods
- DIP: Depend on abstractions, not concretions
- DRY: Don't Repeat Yourself
- YAGNI: You Aren't Gonna Need It
- Composition over Inheritance

#### 5. TDD Protocol

Test-First Workflow:
1. Write failing test demonstrating requirement
2. Implement minimal code to pass test
3. Refactor while keeping tests green
4. Commit only when tests pass

Coverage Requirements:
- Critical paths: 90%+ coverage
- Use targeted tests: `pytest tests/backend/billing/ -v`
- Integration tests for external dependencies

#### 6. Naming Conventions

**Bash/Zsh:**
- File names: snake_case with `.sh` (e.g., `git_help.sh`, `install_docker.sh`)
- Function names: snake_case (e.g., `git_help`, `install_docker`)
- Aliases: dash-form for user commands, mapped from snake_case functions (e.g., `alias git-help='git_help'`)

**Documentation:**
- Markdown files: dash-form (e.g., `setup-guide.md`, `ux-library-notes.md`); avoid camelCase or snake_case

#### 7. Standards & References
- Coding conventions: Link to project docs
- Git strategy: Commit format (Type: Summary)
- Maintenance policy: Update when patterns evolve

#### 8. Context Map (Action-Based Routing)

Format Rules:
- NO tables (use lists)
- NO emojis
- Pattern: `- **[Action/Intent](relative/path)** — When-to-use`

Good vs Bad:
- Bad: `[Edit React Components](./src/components)`
- Good: `[UI Library & Design System](./src/components/AGENTS.md)`

Example:
```markdown
- **[API Routes](./app/api/AGENTS.md)** — Backend handlers and middleware
- **[UI Components](./components/AGENTS.md)** — Frontend library and design
- **[Database Schema](./models/AGENTS.md)** — Schema and migrations
- **[Testing](./tests/AGENTS.md)** — Test utilities and commands
```

### Phase 2: Nested AGENTS.md (CONDITIONAL)

#### Trigger Conditions (ANY ONE)
1. Directory has own dependency file
2. Framework boundary detected
3. Logical boundary with 10+ files, distinct domain
4. Directory depth >= 3, coherent module boundary

#### Skip Conditions (ALL TRUE)
- Single-directory project (depth < 2)
- Total files < 20
- Single tech stack
- No existing nested files
- Trivial directories (< 5 files)

#### Nested File Structure

1. Module Context
   - Purpose: What problem solved?
   - Dependencies: External/internal, versions
   - Ownership: Team/maintainer

2. Tech Stack & Constraints
   - Libraries with version pins
   - Allowed vs forbidden patterns
   - Performance budgets

3. Implementation Patterns
   - Code templates
   - File naming conventions
   - Concrete examples

4. Testing Strategy
   - Targeted test commands
   - Required scenarios: happy path, edge cases, errors

5. Local Golden Rules
   - Module-specific Do's & Don'ts

6. Knowledge/References (Optional)
   - Concept docs, tutorials

### Phase 3: Validation (ALWAYS)

#### Structural Tests
- [ ] Root AGENTS.md exists at project root
- [ ] All required sections present
- [ ] Context Map links valid (relative paths)
- [ ] No circular references

#### Content Tests
- [ ] Each file < 500 lines (HARD STOP)
- [ ] No emojis
- [ ] No tables in Context Maps
- [ ] Valid Markdown syntax
- [ ] Executable commands (verify paths)

#### Semantic Tests
- [ ] Golden Rules include TDD-first
- [ ] SOLID principles explicit (SRP, OCP, LSP, ISP, DIP)
- [ ] Testing commands targeted, not generic
- [ ] Nested files have Module Context and Tests

#### Linting
```bash
# Markdown linter (if enabled in repo - check AGENTS.md for repo override)
tox -e mdlint  # Note: May be disabled in some repos

# Line count - MUST be < 500
wc -l AGENTS.md
```

**Repository Override**: Some repos intentionally disable `tox -e mdlint`. Check the root `AGENTS.md` for policy (search "Markdown linting").

If >500 lines: auto-split into nested files, update Context Map

## Error Handling

### Pre-Flight Safety
Before overwriting:
1. Backup: `.agents.md.backup` with timestamp
2. Preserve Custom Rules: Extract non-standard sections
3. Diff Preview: Show changes summary
4. Conflict Detection: Report bespoke rules lost

### Failure Recovery
- File write permission: Suggest chmod, fallback to stdout
- Invalid directory: Skip, warn, continue
- Circular reference: Break cycle, log chain
- 500-line exceeded: Auto-split, update parent
- Missing test command: Add TODO placeholder

### Rollback
On critical error:
1. Restore all `.agents.md.backup` files
2. Delete partial files from session
3. Output error report: failure point, cause, fix

## Context Map Format (DIP Compliant)

### Why Lists, Not Tables?
1. Token Efficiency: 40% more compact
2. Diff-Friendly: Clean git diffs
3. Parser-Friendly: Simpler regex

Exception: Use tables for comparison matrices (3+ attributes)

### Why No Emojis?
- Token Cost: 2-4 tokens vs 1 for text
- Rendering Inconsistency: Varies by terminal
- Search-Unfriendly: grep doesn't index well

## Execution Workflow

When this skill is invoked:

1. **Analyze** project structure (Phase 0)
2. **Plan & Announce** targets and rationale
3. **Generate** root and nested AGENTS.md (Phases 1-2)
4. **Validate** against all criteria (Phase 3)
5. **Save & Report** summary:
   - Files created/updated with line counts
   - Validation results (pass/fail per check)
   - Manual action items

## Output Requirements

- No conversational text: Only valid Markdown
- No emojis: Strict enforcement
- Diff summary: 3-line change summary before overwrite
- Quality gates: <500 lines, TDD-compliant, SOLID-aligned

## Quick Reference Examples

### Small CLI Tool (< 20 files)
Root only. No nested files.
- Context: Purpose, tech stack
- Commands: build, test, lint
- Golden Rules: Validation, env vars
- TDD: Tests before commit

### Medium Web App (50-100 files)
Root + 2-3 nested (frontend, backend, db).
- Context: Architecture, stack
- Commands: dev, test, build
- Golden Rules: Auth, migrations
- Nested: Per boundary

### Large Microservices (100+ files)
Root + nested per service + cross-cutting.
- Context: Services, orchestration
- Commands: deploy, test-all
- Golden Rules: Communication patterns
- Nested: Per service + shared

## Acceptance Criteria

After generation, verify ALL:
1. New Project: Root created + nested if justified
2. Existing: Backup created, custom preserved
3. Line Limit Exceeded: Auto-split, Map updated
4. Missing Tests: TODO placeholder
5. Circular Reference: Cycle broken, warning logged

## Command

**When invoked, IMMEDIATELY analyze current project and EXECUTE the AGENTS.md system creation following all protocols above.**

Start with Phase 0 analysis and announce plan before proceeding.
