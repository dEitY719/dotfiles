# Medium Project Template

Use for projects with 20–100 files and 2–3 distinct tech domains.
Target: root AGENTS.md (~250 lines) + 2–3 nested AGENTS.md files.

---

## Root AGENTS.md Template

```markdown
# Project Context

- **Objective**: <one-line goal>
- **Stack**: <primary stack>
- **Structure**: <top-level directories with purpose>

# Operational Commands

- **Setup**: `<command>`
- **Dev**: `<command>`
- **Test (all)**: `<command>`
- **Test (targeted)**: `<command with example path>`
- **Lint**: `<command>`
- **Build**: `<command>`

# Golden Rules

## Immutable Constraints
- 500-line limit per AGENTS.md file
- No emojis (token waste)
- <project-specific constraint>
- <project-specific constraint>

## Do's
- DO: <rule 1>
- DO: <rule 2>
- DO: <rule 3>
- DO: Run `<lint command>` before committing

## Don'ts
- DON'T: <rule 1>
- DON'T: <rule 2>
- DON'T: Hardcode paths; use environment variables

# SOLID & Design Principles

- **SRP**: <application>
- **OCP**: <application>
- **DRY**: <application>

# TDD Protocol

1. Write failing test for the requirement
2. Implement minimal code to pass
3. Refactor while keeping tests green
4. Commit only when `<test command>` passes

# Naming Conventions

- **Files**: <pattern>
- **Functions/Classes**: <pattern>
- **Tests**: <pattern, e.g., "test_<module>_<scenario>.py">

# Standards & References

- **Style**: <tool/link>
- **Git**: <commit format>

# Context Map

- **[<Domain 1>](./<dir>/AGENTS.md)** — <when to consult>
- **[<Domain 2>](./<dir>/AGENTS.md)** — <when to consult>
- **[<Domain 3>](./<dir>/AGENTS.md)** — <when to consult> (omit if not needed)
```

---

## Nested AGENTS.md Template

Each nested file covers ONE domain. Keep under 300 lines.

```markdown
# <Module Name> — <one-line purpose>

## Module Context

- **Purpose**: <what problem this module solves>
- **Dependencies**: <external libs with versions>
- **Owner**: <team or person>

## Tech Stack & Constraints

- <library> <version> — <why it's here>
- Allowed: <pattern>
- Forbidden: <anti-pattern>

## Implementation Patterns

<Brief description of the key patterns used here>

```<language>
# Minimal example of the core pattern
```

## Testing Strategy

- **Run**: `<targeted test command>`
- **Required scenarios**: happy path, <domain-specific edge case>, error case

## Local Golden Rules

- DO: <module-specific rule>
- DON'T: <module-specific anti-pattern>
```

---

## Decide What Goes in Nested Files

Ask for each major section in the root draft:
- Does this only apply to one subdirectory? → Move to nested file
- Is it >30 lines of implementation detail? → Move to nested file
- Is it a broad rule that applies everywhere? → Keep in root
