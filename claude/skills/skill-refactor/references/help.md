/skill:refactor — Refactor a SKILL.md to under 100 lines using Progressive Disclosure

Usage:
  /skill:refactor [path/to/SKILL.md]

Arguments:
  [path]    Path to the SKILL.md file to refactor (optional)
            If omitted, searches for SKILL.md from the current directory

Examples:
  /skill:refactor
  /skill:refactor claude/skills/my-skill/SKILL.md
  /skill:refactor help

Options:
  help    Show this message

Note: Always presents a refactoring plan and waits for confirmation before writing files.
