# Small Project Template

Use for projects with <20 files and a single tech stack.
Target: root AGENTS.md only, under 200 lines.

---

## Template

```markdown
# Project Context

- **Objective**: <one-line business/technical goal>
- **Stack**: <tech stack with versions>
- **Structure**: <top-level directory overview>

# Operational Commands

- **Setup**: `<setup command>`
- **Test**: `<test command>`
- **Lint**: `<lint command>`
- **Build**: `<build command>` (omit if not applicable)

# Golden Rules

## Immutable Constraints
- <constraint 1 — e.g., "500-line limit per AGENTS.md">
- <constraint 2 — e.g., "No secrets or credentials">
- <constraint 3 — e.g., "Interactive guard required for bash files">

## Do's
- DO: <specific actionable rule>
- DO: <specific actionable rule>
- DO: <specific actionable rule>

## Don'ts
- DON'T: <specific prohibited pattern>
- DON'T: <specific prohibited pattern>

# SOLID & Design Principles

- **SRP**: <project-specific application>
- **DRY**: <where duplication is most common in this project>
- **YAGNI**: <where over-engineering tends to happen>

# Naming Conventions

- **Files**: <naming pattern, e.g., snake_case.py>
- **Functions**: <naming pattern>
- **Variables**: <naming pattern>

# Standards & References

- **Coding Style**: <link or tool, e.g., "ruff via tox">
- **Git Strategy**: <commit format, e.g., "Conventional Commits">
- **Testing**: <framework and pattern, e.g., "pytest, test-first">
```

## Filling Tips

- Objective: one sentence max. What problem does this solve?
- Stack: include versions. Wrong versions mislead the AI.
- Commands: run them yourself first to confirm they work.
- Immutable Constraints: pick 3 things that, if violated, break everything.
- Do/Don't: be specific. "Write good code" is useless. "Use ux_header() for all output" is useful.
